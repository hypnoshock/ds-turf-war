// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {State} from "cog/IState.sol";
import {Schema, Node} from "@ds/schema/Schema.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {IZone, GAME_STATE, Team} from "./IZone.sol";

import {LibUtils} from "./LibUtils.sol";

using Schema for State;

string constant DATA_BATTLE_START_BLOCK = "battleStartBlock";
string constant DATA_INIT_STATE = "initState";

struct TeamState {
    uint8 team;
    uint8 soldierCount;
}

uint8 constant TEAM_STATE_BIT_LEN = 16;

uint256 constant BATTLE_TIMEOUT_BLOCKS = 300; //60 / BLOCK_TIME_SECS;

library LibCombat {

    function resetStartBlock(Game ds, bytes24 buildingInstance) internal {
        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, DATA_BATTLE_START_BLOCK, bytes32(0)))
        );
    }

    function resetInitState(Game ds, bytes24 buildingInstance) internal {
        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, DATA_INIT_STATE, bytes32(0)))
        );
    }

    function addSoldiers(Game ds, bytes24 buildingInstance, bytes24 actor, uint8 amount) internal {
        State state = ds.getState();

        bytes24 tile = state.getFixedLocation(buildingInstance);
        bytes24 zone = Node.Zone(LibUtils.getTileZone(tile));

        Team team = LibUtils.getUnitTeam(state, zone, actor);

        require(team != Team.NONE, "Base: Player is not in any team");

        // TODO: Check if the player has enough soldiers to add

        if (state.getData(buildingInstance, DATA_BATTLE_START_BLOCK) == bytes32(0)) {
            bytes32 initStateEncoded = state.getData(buildingInstance, DATA_INIT_STATE);
            TeamState[] memory initState;
            if (initStateEncoded == bytes32(0)) {
                initState = new TeamState[](2);
                initState[0].team = uint8(Team.A);
                initState[1].team = uint8(Team.B);
            } else {
                initState = _decodeInitState(initStateEncoded);
            }

            initState[uint8(team) - 1].soldierCount += amount;

            ds.getDispatcher().dispatch(
                abi.encodeCall(
                    Actions.SET_DATA_ON_BUILDING, (buildingInstance, DATA_INIT_STATE, _encodeInitState(initState))
                )
            );
        } else {
            // Update battle state

            ds.getDispatcher().dispatch(
                abi.encodeCall(
                    Actions.SET_DATA_ON_BUILDING,
                    (buildingInstance, LibUtils.getStateChangeKey(block.number), _encodeStateUpdate(team, amount))
                )
            );

            // record our 'random' seed for this block
            ds.getDispatcher().dispatch(
                abi.encodeCall(
                    Actions.SET_DATA_ON_BUILDING,
                    (buildingInstance, LibUtils.getRndSeedKey(block.number), blockhash(block.number - 1))
                )
            );
        }
    }

    function _encodeInitState(TeamState[] memory initState) internal pure returns (bytes32) {
        // TODO: Check if encoded init state is less than 32 bytes
        bytes32 encoded = bytes32(initState.length);
        for (uint256 i = 0; i < initState.length; i++) {
            encoded |= bytes32(
                (uint256(initState[i].team) | uint256(initState[i].soldierCount) << 8) << (8 + (TEAM_STATE_BIT_LEN * i))
            );
        }
        return encoded;
    }

    function _decodeInitState(bytes32 initStateEncoded) internal pure returns (TeamState[] memory) {
        uint8 length = uint8(uint256(initStateEncoded) & 0xff);
        TeamState[] memory initState = new TeamState[](length);
        for (uint8 i = 0; i < length; i++) {
            uint256 teamStateEncoded = uint256(initStateEncoded >> (8 + (TEAM_STATE_BIT_LEN * i)));
            initState[i].team = uint8(teamStateEncoded & 0xff);
            initState[i].soldierCount = uint8((teamStateEncoded >> 8) & 0xff);
        }
        return initState;
    }

    function _encodeStateUpdate(Team team, uint8 soldierAmount) internal pure returns (bytes32) {
        return bytes32(uint256(team) | (uint256(soldierAmount) << 8));
    }

    function _decodeStateUpdate(bytes32 stateUpdate) internal pure returns (Team team, uint8 soldierAmount) {
        return (Team(uint8(uint256(stateUpdate))), uint8(uint256(stateUpdate) >> 8));
    }

    function getBattleState(Game ds, bytes24 buildingInstance, uint256 blockNumber)
        internal
        returns (TeamState[] memory teamStates, bool isFinished)
    {
        State state = ds.getState();

        bytes32 initStateEncoded = state.getData(buildingInstance, DATA_INIT_STATE);
        if (initStateEncoded == bytes32(0)) {
            teamStates = new TeamState[](2);
            teamStates[0].team = uint8(Team.A);
            teamStates[1].team = uint8(Team.B);
        } else {
            teamStates = _decodeInitState(initStateEncoded);
        }

        uint256 startBlock = uint256(state.getData(buildingInstance, DATA_BATTLE_START_BLOCK));
        if (startBlock == 0) {
            return (teamStates, false);
        }

        uint256 totalBlocks = blockNumber - startBlock;
        if (totalBlocks > BATTLE_TIMEOUT_BLOCKS) {
            totalBlocks = BATTLE_TIMEOUT_BLOCKS;

            // battle has timed out so ends even if both sides still have soldiers
            isFinished = true;
        }

        // TODO: Find the team that is on defence so we know who attacks first

        uint256 rndSeed = uint256(state.getData(buildingInstance, LibUtils.getRndSeedKey(startBlock)));
        for (uint256 i = 0; i < totalBlocks; i++) {
            bytes32 stateUpdate = state.getData(buildingInstance, LibUtils.getStateChangeKey(startBlock + i));
            if (stateUpdate != bytes32(0)) {
                (Team team, uint8 soldierAmount) = _decodeStateUpdate(stateUpdate);
                teamStates[uint8(team) - 1].soldierCount += soldierAmount;
                rndSeed = uint256(state.getData(buildingInstance, LibUtils.getRndSeedKey(startBlock + i)));
            }

            rndSeed = uint256(keccak256(abi.encodePacked(rndSeed, i)));

            if (teamStates[uint8(Team.A) - 1].soldierCount == 0 || teamStates[uint8(Team.B) - 1].soldierCount == 0) {
                return (teamStates, i > 0);
            }

            if (rndSeed & 0xff > 127) {
                teamStates[uint8(Team.B) - 1].soldierCount--;
                if (teamStates[uint8(Team.B) - 1].soldierCount == 0) {
                    return (teamStates, true);
                }
            } else {
                teamStates[uint8(Team.A) - 1].soldierCount--;
                if (teamStates[uint8(Team.A) - 1].soldierCount == 0) {
                    return (teamStates, true);
                }
            }
        }

        return (teamStates, isFinished);
    }

    function startBattle(Game ds, bytes24 buildingInstance) internal {
        State state = ds.getState();

        bytes24 tile = state.getFixedLocation(buildingInstance);
        (int16 z,,,) = LibUtils.getTileCoords(tile);

        bytes24 zoneID = Node.Zone(z);
        {
            IZone zoneImpl = IZone(state.getImplementation(zoneID));
            require(
                zoneImpl.getGameState(state, zoneID) == GAME_STATE.IN_PROGRESS,
                "Base: Cannot start battle when game has ended"
            );
        }

        require(
            state.getData(buildingInstance, DATA_BATTLE_START_BLOCK) == bytes32(0), "Base: Battle has already started"
        );

        ds.getDispatcher().dispatch(
            abi.encodeCall(
                Actions.SET_DATA_ON_BUILDING, (buildingInstance, DATA_BATTLE_START_BLOCK, bytes32(block.number))
            )
        );

        // record our 'random' seed for this block
        ds.getDispatcher().dispatch(
            abi.encodeCall(
                Actions.SET_DATA_ON_BUILDING,
                (buildingInstance, LibUtils.getRndSeedKey(block.number), blockhash(block.number - 1))
            )
        );
    }

    function continueBattle(Game ds, bytes24 buildingInstance) internal {
        State state = ds.getState();

        require(
            state.getData(buildingInstance, DATA_BATTLE_START_BLOCK) != bytes32(0), "Base: Battle not started"
        );

        (TeamState[] memory teamStates, bool isFinished) = getBattleState(ds, buildingInstance, block.number);

        require(isFinished, "Base: Battle still in play");

        require(teamStates[0].soldierCount > 0 && teamStates[1].soldierCount > 0, "Base: cannot continue a finished battle");

        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, DATA_INIT_STATE, _encodeInitState(teamStates)))
        );

        ds.getDispatcher().dispatch(
            abi.encodeCall(
                Actions.SET_DATA_ON_BUILDING, (buildingInstance, DATA_BATTLE_START_BLOCK, bytes32(block.number))
            )
        );

        // record our 'random' seed for this block
        ds.getDispatcher().dispatch(
            abi.encodeCall(
                Actions.SET_DATA_ON_BUILDING,
                (buildingInstance, LibUtils.getRndSeedKey(block.number), blockhash(block.number - 1))
            )
        );
    }

}