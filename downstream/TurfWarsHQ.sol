// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {State} from "cog/IState.sol";
import {Dispatcher} from "cog/IDispatcher.sol";
import {Schema, Node, CompoundKeyDecoder, BLOCK_TIME_SECS} from "@ds/schema/Schema.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {BuildingKind} from "@ds/ext/BuildingKind.sol";
import {LibString} from "./LibString.sol";
import {LibUtils} from "./LibUtils.sol";
import {IZone, GAME_STATE, DATA_SELECTED_LEVEL, DATA_HAS_CLAIMED_PRIZES, TEAM_A, TEAM_B} from "./IZone.sol";
import {IBase} from "./IBase.sol";

using Schema for State;

contract TurfWarsHQ is BuildingKind {

    int16 constant MAP_RADIUS = 7;

    function claimPrizes() external {}

    function use(Game ds, bytes24 buildingInstance, bytes24 /*actor*/, bytes calldata payload) public override {
        if ((bytes4)(payload) == this.claimPrizes.selector) {
            _claimPrizes(ds, buildingInstance);
        } else {
            revert("Invalid function selector");
        }
    }

    function _claimPrizes(Game ds, bytes24 buildingInstance) internal {
        State state = ds.getState();

        bytes24 tile = state.getFixedLocation(buildingInstance);
        (int16 z, int16 q, int16 r, /*int16 s*/) = LibUtils.getTileCoords(tile);

        bytes24 zoneID = Node.Zone(z);

        IZone zoneImpl = IZone(state.getImplementation(zoneID));
        require(zoneImpl.getGameState(state, zoneID) == GAME_STATE.FINISHED, "TurfWarsHQ: Cannot claim prizes before the game is over");
        require(state.getData(zoneID, DATA_HAS_CLAIMED_PRIZES) == bytes32(0), "TurfWarsHQ: Prizes already claimed");

        (uint256 teamAScore, uint256 teamBScore) = _getScores(state, zoneID, z, q, r, MAP_RADIUS);

        if (teamAScore == teamBScore) {
            // draw
            zoneImpl.setHasClaimedPrizes(ds, zoneID);
            return;
        }

        string memory winningTeam = teamAScore > teamBScore ? TEAM_A : TEAM_B;
        uint64 teamLength = uint64(uint256(state.getData(zoneID, string(abi.encodePacked(winningTeam, "Length")))));

        zoneImpl.spawnPrizes(ds, tile, teamLength);
        _movePrizesToBuilding(ds, tile, buildingInstance, teamLength);
        _airDrop(ds, zoneID, buildingInstance, winningTeam, teamLength);

        zoneImpl.setHasClaimedPrizes(ds, zoneID);
    }

    function _movePrizesToBuilding(Game ds, bytes24 tile, bytes24 buildingInstance, uint64 count) internal {
        Dispatcher dispatcher = ds.getDispatcher();
        dispatcher.dispatch(
            abi.encodeCall(
                Actions.TRANSFER_ITEM_MOBILE_UNIT,
                (
                    buildingInstance, // bytes24 mobileUnit,
                    [tile, buildingInstance], // bytes24[2] calldata equipees,
                    [0, 0], // uint8[2] calldata equipSlots,
                    [0, 0], // uint8[2] calldata itemSlots,
                    bytes24(0), // bytes24 toBagId, (only needed if we want to create this bag)
                    count // uint64 qty
                )
            )
        );
    }

    function _airDrop(Game ds, bytes24 zoneID, bytes24 buildingInstance, string memory teamPrefix, uint64 teamLength) internal {
        Dispatcher dispatcher = ds.getDispatcher();
        State state = ds.getState();

        for (uint64 i = 0; i < teamLength; i++) {
            string memory teamUnitIndex = string(abi.encodePacked(teamPrefix, "Unit_", LibString.toString(i)));
            address ownerAddress = state.getOwnerAddress(state.getOwner(bytes24(state.getData(zoneID, teamUnitIndex))));

            dispatcher.dispatch(
                abi.encodeCall(
                    Actions.EXPORT_ITEM,
                    (
                        buildingInstance, // from equipee
                        0, // equipSlot
                        0, // fromItemSlot
                        ownerAddress, // to
                        1 // qty
                    )
                )
            );
        }
    }

    function _getScores(State state, bytes24 zoneID, int16 originZ, int16 originQ, int16 originR, int16 range) internal view returns (uint256 teamAScore, uint256 teamBScore) {
        for (int16 q = originQ - range; q <= originQ + range; q++) {
            for (int16 r = originR - range; r <= originR + range; r++) {
                int16 s = -q - r;
                bytes24 nextTile = Node.Tile(originZ, q, r, s);
                bytes24 winningUnit = bytes24(state.getData(zoneID, LibUtils.getTileWinnerKey(nextTile)));
                if (winningUnit == bytes24(0)) {
                    continue;
                }

                if (LibUtils.isUnitInTeam(state, zoneID, TEAM_A, winningUnit)) {
                    teamAScore++;
                } else {
                    teamBScore++;
                }
            }
        }
    }

    // function _debugLogScores(Game ds, bytes24 buildingInstance, uint256 teamAScore, uint256 teamBScore) internal {
    //     ds.getDispatcher().dispatch(
    //         abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, "teamAScore", bytes32(teamAScore)))
    //     );
    //     ds.getDispatcher().dispatch(
    //         abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, "teamBScore", bytes32(teamBScore)))
    //     );
    // }

}
