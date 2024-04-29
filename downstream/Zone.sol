// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {Dispatcher} from "cog/IDispatcher.sol";
import {State, CompoundKeyDecoder} from "cog/IState.sol";
import {Schema, CombatWinState, Node} from "@ds/schema/Schema.sol";
import {ZoneKind} from "@ds/ext/ZoneKind.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {LibUtils} from "./LibUtils.sol";
import "@ds/utils/LibString.sol";

using Schema for State;

contract TurfWars is ZoneKind {
    function join() external {}
    function start() external {}
    function claim() external {}
    function reset() external {}

    enum GAME_STATE {NOT_STARTED, IN_PROGRESS, FINISHED}

    function use(Game ds, bytes24 zoneID, bytes24 mobileUnitID, bytes calldata payload) public override {
        State state = ds.getState();
        if ((bytes4)(payload) == this.join.selector) {
            _join(ds, state, mobileUnitID, zoneID);
        } 
    }

    function _join(Game ds, State state, bytes24 unitID, bytes24 zoneID) private {
        // check game not in progress
        if (GAME_STATE(uint256(state.getData(zoneID, "gameState"))) != GAME_STATE.NOT_STARTED) revert("Cannot join game in progress");

        // Check if unit has already joined
        if (
            _isUnitInTeam(state, zoneID, "teamA", unitID) || _isUnitInTeam(state, zoneID, "teamB", unitID)
        ) {
            revert("Already joined");
        }

        uint64 teamALength = uint64(uint256(state.getData(zoneID, "teamALength")));
        uint64 teamBLength = uint64(uint256(state.getData(zoneID, "teamBLength")));

        // assign a team
        _assignUnitToTeam(
            ds,
            (teamALength <= teamBLength) ? "teamA" : "teamB",
            (teamALength <= teamBLength) ? teamALength : teamBLength,
            unitID,
            zoneID
        );
    }

    function _assignUnitToTeam(Game ds, string memory team, uint64 teamLength, bytes24 unitID, bytes24 zoneID)
        internal
    {
        Dispatcher dispatcher = ds.getDispatcher();
        // TODO: Do we need to keccak this?
        if (keccak256(abi.encodePacked(team)) == keccak256(abi.encodePacked("teamA"))) {
            _processTeam(dispatcher, zoneID, "teamA", teamLength, unitID);
        } else if (keccak256(abi.encodePacked(team)) == keccak256(abi.encodePacked("teamB"))) {
            _processTeam(dispatcher, zoneID, "teamB", teamLength, unitID);
        }
    }

    function _processTeam(
        Dispatcher dispatcher,
        bytes24 zoneID,
        string memory teamPrefix,
        uint64 teamLength,
        bytes24 unitID
    ) private {
        // adding to teamXUnit_X
        string memory teamUnitIndex =
            string(abi.encodePacked(teamPrefix, "Unit_", LibString.toString(uint256(teamLength))));
        _setDataOnZone(dispatcher, zoneID, teamUnitIndex, bytes32(unitID));
        _setDataOnZone(
            dispatcher, zoneID, string(abi.encodePacked(teamPrefix, "Length")), bytes32(uint256(teamLength) + 1)
        );
    }

    function _isUnitInTeam(State state, bytes24 zoneID, string memory teamPrefix, bytes24 unitId)
        private
        view
        returns (bool)
    {
        uint64 teamLength = uint64(uint256(state.getData(zoneID, string(abi.encodePacked(teamPrefix, "Length")))));
        // check every slot for unit id
        for (uint64 i = 0; i < teamLength; i++) {
            string memory teamUnitIndex = string(abi.encodePacked(teamPrefix, "Unit_", LibString.toString(i)));
            if (bytes24(state.getData(zoneID, teamUnitIndex)) == unitId) {
                return true;
            }
        }
        return false;
    }

    function getTileCoords(bytes24 tile) internal pure returns (int16, int16, int16, int16) {
        int16[4] memory keys = CompoundKeyDecoder.INT16_ARRAY(tile);
        return (keys[0], keys[1], keys[2], keys[3]);
    }

    // -- Hooks

    function onUnitArrive(Game ds, bytes24 zoneID, bytes24 mobileUnitID) external override {
        State state = ds.getState();
        bytes24 player = state.getOwner(mobileUnitID);
        // address playerAddress = state.getOwnerAddress(player);
        bytes24 mobileUnitTile = state.getCurrentLocation(mobileUnitID, uint64(block.number));
        (int16 z,,,) = getTileCoords(mobileUnitTile);

        // Check game has started and check that the player is in the game
        if (mobileUnitTile != Node.Tile(z, 0, 0, 0)) {
            // Don't allow players to move before game has started
            if (GAME_STATE(uint256(state.getData(zoneID, "gameState"))) == GAME_STATE.NOT_STARTED) {
                // Allow players to move to the starting tile
                // TODO: Make these positions configurable / dynamic
                if (_isUnitInTeam(state, zoneID, "teamA", mobileUnitID) && mobileUnitTile == Node.Tile(z, 0, -5, 5)) {
                    return;
                } else if (_isUnitInTeam(state, zoneID, "teamB", mobileUnitID) && mobileUnitTile == Node.Tile(z, 0, 5, -5)) {
                    return;
                } 
                revert("Unit cannot move, Game not started");
            }

            if (GAME_STATE(uint256(state.getData(zoneID, "gameState"))) == GAME_STATE.IN_PROGRESS) {
                if (!_isUnitInTeam(state, zoneID, "teamA", mobileUnitID) && !_isUnitInTeam(state, zoneID, "teamB", mobileUnitID)) {
                    revert("Unit not in game");
                }
            }

            // Claim tile
            if (!_hasTileBeenWon(ds, mobileUnitTile, zoneID)) {
                _setTileWinner(ds, mobileUnitTile, player, zoneID);
            }
        }
    }

    function _hasTileBeenWon(Game ds, bytes24 tile, bytes24 zoneID) internal returns (bool) {
        return ds.getState().getData(zoneID, LibUtils.getTileWinnerKey(tile)) != bytes32(0);
    }

    function _setTileWinner(Game ds, bytes24 tile, bytes24 player, bytes24 zoneID) internal {
        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_ZONE, (zoneID, LibUtils.getTileWinnerKey(tile), player))
        );
    }

    function _increment(Game ds, bytes24 zoneID, string memory name) internal {
        State state = ds.getState();

        uint256 count = uint256(state.getData(zoneID, name));
        ds.getDispatcher().dispatch(abi.encodeCall(Actions.SET_DATA_ON_ZONE, (zoneID, name, bytes32(count + 1))));
    }

    function _setDataOnZone(Dispatcher dispatcher, bytes24 zoneID, string memory key, bytes32 value) internal {
        dispatcher.dispatch(abi.encodeCall(Actions.SET_DATA_ON_ZONE, (zoneID, key, value)));
    }
}
