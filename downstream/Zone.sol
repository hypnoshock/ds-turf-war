// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {Dispatcher} from "cog/IDispatcher.sol";
import {State, CompoundKeyDecoder} from "cog/IState.sol";
import {Schema, CombatWinState, Node} from "@ds/schema/Schema.sol";
import {ZoneKind} from "@ds/ext/ZoneKind.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {LibUtils} from "./LibUtils.sol";
import {IZone} from "./IZone.sol";
import "@ds/utils/LibString.sol";

using Schema for State;

contract TurfWarsZone is ZoneKind, IZone {
    function join() external {}
    function setReady() external {}
    function unsetReady() external {}
    // function claim() external {}
    // function reset() external {}
    
    enum Team {NONE, A, B}
    string constant TEAM_A = "teamA";
    string constant TEAM_B = "teamB";

    // Data keys
    string constant DATA_GAME_STATE = "gameState";
    string constant DATA_READY = "ready";

    enum GAME_STATE {NOT_STARTED, IN_PROGRESS, FINISHED}

    function use(Game ds, bytes24 zoneID, bytes24 mobileUnitID, bytes calldata payload) public override {
        State state = ds.getState();
        if ((bytes4)(payload) == this.join.selector) {
            _join(ds, state, mobileUnitID, zoneID);
        } else if ((bytes4)(payload) == this.setReady.selector) {
            _setReady(ds, state, mobileUnitID, zoneID);
        } else if ((bytes4)(payload) == this.unsetReady.selector) {
            _unsetReady(ds, state, mobileUnitID, zoneID);
        } 
    }

    // TODO: only bases can call this
    function setAreaWinner(Game ds, bytes24 origin, bytes24 player) public {
        (int16 z, int16 q, int16 r, int16 s) = getTileCoords(origin);
        bytes24 zoneID = Node.Zone(z);
        bytes24 tile;

        tile = Node.Tile(z, q, r, s);
        if (!_hasTileBeenWon(ds, tile, zoneID))
            _setTileWinner(ds, tile, player, Node.Zone(z));

        tile = Node.Tile(z, q + 0, r + 1, s + -1);
        if (!_hasTileBeenWon(ds, tile, zoneID))
            _setTileWinner(ds, tile, player, Node.Zone(z));

        tile = Node.Tile(z, q + 1, r + 0, s + -1);
        if (!_hasTileBeenWon(ds, tile, zoneID))            
            _setTileWinner(ds, tile, player, Node.Zone(z));

        tile = Node.Tile(z, q + 1, r + -1, s + 0);
        if (!_hasTileBeenWon(ds, tile, zoneID))            
            _setTileWinner(ds, tile, player, Node.Zone(z));

        tile = Node.Tile(z, q + 0, r + -1, s + 1);
        if (!_hasTileBeenWon(ds, tile, zoneID))            
            _setTileWinner(ds, tile, player, Node.Zone(z));

        tile = Node.Tile(z, q + -1, r + 0, s + 1);
        if (!_hasTileBeenWon(ds, tile, zoneID))            
            _setTileWinner(ds, tile, player, Node.Zone(z));

        tile = Node.Tile(z, q + -1, r + 1, s + 0);
        if (!_hasTileBeenWon(ds, tile, zoneID))            
            _setTileWinner(ds, tile, player, Node.Zone(z));
    }

    function _setReady(Game ds, State state, bytes24 mobileUnitID, bytes24 zoneID) private {
        // Check if game is already in progress
        if (GAME_STATE(uint256(state.getData(zoneID, DATA_GAME_STATE))) != GAME_STATE.NOT_STARTED) {
            revert("Game already in progress");
        }
        
        // TODO: Check if caller is the owner of the unit
        // if (state.getOwner(mobileUnitID) != Node.Player(msg.sender)) {
        //     revert("Not owner of unit");
        // }
        
        // Get unit team
        Team team = _getUnitTeam(state, zoneID, mobileUnitID);
        if (team == Team.NONE) {
            revert("Unit not in team");
        }

        // Check if other team is ready
        if (Team(uint256(state.getData(zoneID, DATA_READY))) == (team == Team.A ? Team.B : Team.A)) {
            // Other team ready, start game
            _setDataOnZone(ds.getDispatcher(), zoneID, DATA_GAME_STATE, bytes32(uint256(GAME_STATE.IN_PROGRESS)));
        } else {
            // Set team as ready
            _setDataOnZone(ds.getDispatcher(), zoneID, DATA_READY, bytes32(uint256(team)));
        }
    }

    function _unsetReady(Game ds, State state, bytes24 mobileUnitID, bytes24 zoneID) private {
        // Check if game is already in progress
        if (GAME_STATE(uint256(state.getData(zoneID, DATA_GAME_STATE))) != GAME_STATE.NOT_STARTED) {
            revert("Game already in progress");
        }
        
        // TODO: Check if caller is the owner of the unit
        // if (state.getOwner(mobileUnitID) != Node.Player(msg.sender)) {
        //     revert("Not owner of unit");
        // }
        
        // Get unit team
        Team team = _getUnitTeam(state, zoneID, mobileUnitID);
        if (team == Team.NONE) {
            revert("Unit not in team");
        }

        // Check that the team was set to ready
        require (Team(uint256(state.getData(zoneID, DATA_READY))) == team, "Team not ready");

        _setDataOnZone(ds.getDispatcher(), zoneID, DATA_READY, bytes32(uint256(Team.NONE)));
    }

    function _join(Game ds, State state, bytes24 unitID, bytes24 zoneID) private {
        // check game not in progress
        if (GAME_STATE(uint256(state.getData(zoneID, DATA_GAME_STATE))) != GAME_STATE.NOT_STARTED) revert("Cannot join game in progress");

        // Check if unit has already joined
        if (
            _isUnitInTeam(state, zoneID, TEAM_A, unitID) || _isUnitInTeam(state, zoneID, TEAM_B, unitID)
        ) {
            revert("Already joined");
        }

        uint64 teamALength = uint64(uint256(state.getData(zoneID, "teamALength")));
        uint64 teamBLength = uint64(uint256(state.getData(zoneID, "teamBLength")));

        // assign a team
        _assignUnitToTeam(
            ds,
            (teamALength <= teamBLength) ? TEAM_A : TEAM_B,
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
        if (keccak256(abi.encodePacked(team)) == keccak256(abi.encodePacked(TEAM_A))) {
            _processTeam(dispatcher, zoneID, TEAM_A, teamLength, unitID);
        } else if (keccak256(abi.encodePacked(team)) == keccak256(abi.encodePacked(TEAM_B))) {
            _processTeam(dispatcher, zoneID, TEAM_B, teamLength, unitID);
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

    function _getUnitTeam(State state, bytes24 zoneID, bytes24 unitId) private view returns (Team) {
        if (_isUnitInTeam(state, zoneID, TEAM_A, unitId)) {
            return Team.A;
        } else if (_isUnitInTeam(state, zoneID, TEAM_B, unitId)) {
            return Team.B;
        }
        return Team.NONE;
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
            if (GAME_STATE(uint256(state.getData(zoneID, DATA_GAME_STATE))) == GAME_STATE.NOT_STARTED) {
                // Allow players to move to the starting tile
                // TODO: Make these positions configurable / dynamic
                if (_isUnitInTeam(state, zoneID, TEAM_A, mobileUnitID) && mobileUnitTile == Node.Tile(z, 0, -5, 5)) {
                    return;
                } else if (_isUnitInTeam(state, zoneID, TEAM_B, mobileUnitID) && mobileUnitTile == Node.Tile(z, 0, 5, -5)) {
                    return;
                } 
                revert("Unit cannot move, Game not started");
            }

            if (GAME_STATE(uint256(state.getData(zoneID, DATA_GAME_STATE))) == GAME_STATE.IN_PROGRESS) {
                if (!_isUnitInTeam(state, zoneID, TEAM_A, mobileUnitID) && !_isUnitInTeam(state, zoneID, TEAM_B, mobileUnitID)) {
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
