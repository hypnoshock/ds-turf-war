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
import {IZone, GAME_STATE, DATA_SELECTED_LEVEL, DATA_HAS_CLAIMED_PRIZES, Team, TEAM_A, TEAM_B} from "./IZone.sol";
import {IBase} from "./IBase.sol";
import {LibPerson, PersonState} from "./LibPerson.sol";
import {LibInventory} from "./LibInventory.sol";
import {LibCombat} from "./LibCombat.sol";
import {Weapon} from "./LibCombat.sol";

import {ABDKMath64x64} from "./libs/ABDKMath64x64.sol";

using Schema for State;
using ABDKMath64x64 for int128;

uint256 constant MAX_ELAPSED_BLOCKS = (60 * 60) / 2; // 1 hour
string constant DATA_BUILD_UPDATE_BLOCK = "buildUpdateBlock";
string constant DATA_BUILD_PERC = "buildPerc";

library LibConstruction {
    function setIsBuilt(Game ds, bytes24 buildingInstance, bool val) internal {
        setData(ds, buildingInstance, DATA_BUILD_PERC, uint256(int256(ABDKMath64x64.fromUInt(val ? 100 : 0))));
    }

    // NOTE: only returns true if data has been set to 100%
    function getIsBuilt(Game ds, bytes24 buildingInstance) internal returns (bool) {
        return int128(int256(uint256(ds.getState().getData(buildingInstance, DATA_BUILD_PERC))))
            == ABDKMath64x64.fromUInt(100);
    }

    function getBuildState(Game ds, bytes24 buildingInstance) internal returns (int128) {
        State state = ds.getState();

        int128 buildPerc = int128(int256(uint256(state.getData(buildingInstance, DATA_BUILD_PERC))));
        if (buildPerc == ABDKMath64x64.fromUInt(100)) {
            return buildPerc;
        }

        // construction halts when in combat
        if (LibCombat.hasCombatStarted(ds, buildingInstance)) {
            return buildPerc;
        }

        uint256 lastUpdateBlock = uint256(state.getData(buildingInstance, DATA_BUILD_UPDATE_BLOCK));
        if (lastUpdateBlock == 0) {
            return 0;
        }

        // Get number of people in the building
        PersonState[] memory personStates = LibPerson.getPersonStates(ds, buildingInstance, block.number);

        // NOTE: This would be counting everyone in the building not just the team's people. Doesn't matter though
        uint16 personCount;
        for (uint8 i = 0; i < personStates.length; i++) {
            personCount += personStates[i].count;
        }

        if (personCount == 0) {
            return buildPerc;
        }

        uint256 elapsedBlocks = block.number - lastUpdateBlock;
        if (elapsedBlocks > MAX_ELAPSED_BLOCKS) {
            elapsedBlocks = MAX_ELAPSED_BLOCKS;
        }

        buildPerc += ABDKMath64x64.divu(1, 100).mul(ABDKMath64x64.fromUInt(elapsedBlocks)).mul(
            ABDKMath64x64.fromUInt(personCount)
        );

        if (buildPerc >= ABDKMath64x64.fromUInt(100)) {
            return ABDKMath64x64.fromUInt(100);
        }

        return buildPerc;
    }

    function updateBuildState(Game ds, bytes24 buildingInstance) internal {
        int128 buildPerc = getBuildState(ds, buildingInstance);
        setData(ds, buildingInstance, DATA_BUILD_PERC, uint256(int256(buildPerc)));
        setData(ds, buildingInstance, DATA_BUILD_UPDATE_BLOCK, uint256(block.number));
    }

    function setData(Game ds, bytes24 buildingInstance, string memory key, uint256 value) private {
        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, key, bytes32(value)))
        );
    }
}
