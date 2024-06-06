// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {State} from "cog/IState.sol";
import {Schema, Node} from "@ds/schema/Schema.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {IZone, GAME_STATE, Team} from "./IZone.sol";

import {LibUtils} from "./LibUtils.sol";

using Schema for State;

bytes24 constant SOLDIER_ITEM = 0x6a7a67f05c334a0b000000010000000a0000000a00000028;

string constant DATA_BATTLE_START_BLOCK = "battleStartBlock";
string constant DATA_INIT_STATE = "initState";

enum Weapon {
    None,
    Rock,
    Slingshot,
    Spear,
    Longbow
}

uint8 constant NUM_WEAPON_KINDS = 5;
uint8 constant NUM_DEFENCE_LEVELS = 3;

struct BattalionState {
    uint8 team;
    uint8 soldierCount;
    uint8[NUM_WEAPON_KINDS] weapons;
    uint8[NUM_DEFENCE_LEVELS] defence;
}

// NOTE: If encoding state in one 32 byte slot, we can only have 3 teams
uint8 constant BATTALION_STATE_BIT_LEN = 16 + (8 * NUM_WEAPON_KINDS) + (8 * NUM_DEFENCE_LEVELS);

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

    function setInitState(Game ds, bytes24 buildingInstance, BattalionState[] memory initState) internal {
        ds.getDispatcher().dispatch(
            abi.encodeCall(
                Actions.SET_DATA_ON_BUILDING, (buildingInstance, DATA_INIT_STATE, _encodeInitState(initState))
            )
        );
    }

    function addSoldiers(
        Game ds,
        bytes24 buildingInstance,
        bytes24 actor,
        uint8 amount,
        uint8[NUM_WEAPON_KINDS] memory weapons,
        uint8[NUM_DEFENCE_LEVELS] memory defence
    ) internal {
        State state = ds.getState();

        bytes24 tile = state.getFixedLocation(buildingInstance);
        bytes24 zone = Node.Zone(LibUtils.getTileZone(tile));

        Team team = LibUtils.getUnitTeam(state, zone, actor);

        require(team != Team.NONE, "Base: Player is not in any team");

        if (state.getData(buildingInstance, DATA_BATTLE_START_BLOCK) == bytes32(0)) {
            bytes32 initStateEncoded = state.getData(buildingInstance, DATA_INIT_STATE);
            BattalionState[] memory initState;
            if (initStateEncoded == bytes32(0)) {
                initState = new BattalionState[](2);
                initState[0].team = uint8(Team.A);
                initState[1].team = uint8(Team.B);
            } else {
                initState = _decodeInitState(initStateEncoded);
            }

            initState[uint8(team) - 1].soldierCount += amount;

            // Add weapons
            for (uint8 i = 0; i < NUM_WEAPON_KINDS; i++) {
                initState[uint8(team) - 1].weapons[i] += weapons[i];
            }

            // Add defence
            for (uint8 i = 0; i < NUM_DEFENCE_LEVELS; i++) {
                initState[uint8(team) - 1].defence[i] += defence[i];
            }

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
                    (
                        buildingInstance,
                        LibUtils.getStateChangeKey(block.number),
                        bytes32(_encodeBattalionState(BattalionState(uint8(team), amount, weapons, defence)))
                    )
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

    function _encodeInitState(BattalionState[] memory initState) internal pure returns (bytes32) {
        bytes32 encodedInitState = bytes32(initState.length);
        for (uint256 i = 0; i < initState.length; i++) {
            uint256 encodedBattalionState = _encodeBattalionState(initState[i]);
            encodedInitState |= bytes32(encodedBattalionState << (8 + (BATTALION_STATE_BIT_LEN * i)));
        }
        return encodedInitState;
    }

    function _decodeInitState(bytes32 initStateEncoded) internal pure returns (BattalionState[] memory) {
        uint8 length = uint8(uint256(initStateEncoded) & 0xff);
        BattalionState[] memory initState = new BattalionState[](length);
        for (uint8 i = 0; i < length; i++) {
            uint256 battalionStateEncoded = uint256(initStateEncoded >> (8 + (BATTALION_STATE_BIT_LEN * i)));
            initState[i] = _decodeBattalionState(battalionStateEncoded);
        }
        return initState;
    }

    function _encodeBattalionState(BattalionState memory battalionState) internal pure returns (uint256) {
        uint256 encodedBattalionState = uint256(battalionState.team) | uint256(battalionState.soldierCount) << 8;
        for (uint8 j = 0; j < NUM_WEAPON_KINDS; j++) {
            encodedBattalionState |= uint256(battalionState.weapons[j]) << (16 + (8 * j));
        }
        for (uint8 j = 0; j < NUM_DEFENCE_LEVELS; j++) {
            encodedBattalionState |= uint256(battalionState.defence[j]) << (16 + (8 * NUM_WEAPON_KINDS) + (8 * j));
        }
        return encodedBattalionState;
    }

    function _decodeBattalionState(uint256 battalionStateEncoded)
        internal
        pure
        returns (BattalionState memory battalionState)
    {
        battalionState.team = uint8(battalionStateEncoded & 0xff);
        battalionState.soldierCount = uint8((battalionStateEncoded >> 8) & 0xff);
        for (uint8 j = 0; j < NUM_WEAPON_KINDS; j++) {
            battalionState.weapons[j] = uint8((battalionStateEncoded >> (16 + (8 * j)) & 0xff));
        }
        for (uint8 j = 0; j < NUM_DEFENCE_LEVELS; j++) {
            battalionState.defence[j] = uint8((battalionStateEncoded >> (16 + (8 * NUM_WEAPON_KINDS) + (8 * j)) & 0xff));
        }
    }

    function getBattleState(Game ds, bytes24 buildingInstance, uint256 blockNumber)
        internal
        returns (BattalionState[] memory battalionStates, bool isFinished)
    {
        State state = ds.getState();

        bytes32 initStateEncoded = state.getData(buildingInstance, DATA_INIT_STATE);
        if (initStateEncoded == bytes32(0)) {
            battalionStates = new BattalionState[](2);
            battalionStates[0].team = uint8(Team.A);
            battalionStates[1].team = uint8(Team.B);
        } else {
            battalionStates = _decodeInitState(initStateEncoded);
        }

        uint256 startBlock = uint256(state.getData(buildingInstance, DATA_BATTLE_START_BLOCK));
        if (startBlock == 0) {
            return (battalionStates, false);
        }

        uint256 totalBlocks = blockNumber - startBlock;
        if (totalBlocks > BATTLE_TIMEOUT_BLOCKS) {
            totalBlocks = BATTLE_TIMEOUT_BLOCKS;

            // battle has timed out so ends even if both sides still have soldiers
            isFinished = true;
        }

        uint256 rndSeed = uint256(state.getData(buildingInstance, LibUtils.getRndSeedKey(startBlock)));
        for (uint256 i = 0; i < totalBlocks; i++) {
            uint256 stateUpdate = uint256(state.getData(buildingInstance, LibUtils.getStateChangeKey(startBlock + i)));
            if (stateUpdate != 0) {
                BattalionState memory battalionState = _decodeBattalionState(stateUpdate);

                battalionStates[battalionState.team - 1].soldierCount += battalionState.soldierCount;
                for (uint8 j = 0; j < NUM_WEAPON_KINDS; j++) {
                    battalionStates[battalionState.team - 1].weapons[j] += battalionState.weapons[j];
                }
                for (uint8 j = 0; j < NUM_DEFENCE_LEVELS; j++) {
                    battalionStates[battalionState.team - 1].defence[j] += battalionState.defence[j];
                }
                rndSeed = uint256(state.getData(buildingInstance, LibUtils.getRndSeedKey(startBlock + i)));
            }

            rndSeed = uint256(keccak256(abi.encodePacked(rndSeed, i)));

            if (
                battalionStates[uint8(Team.A) - 1].soldierCount == 0
                    || battalionStates[uint8(Team.B) - 1].soldierCount == 0
            ) {
                return (battalionStates, true);
            }

            // Both sides have equal chance of striking regardless of the number of soldiers on their side
            if (rndSeed & 0xff > 127) {
                // Team A strikes
                battalionStates[uint8(Team.B) - 1].soldierCount--;
                if (battalionStates[uint8(Team.B) - 1].soldierCount == 0) {
                    return (battalionStates, true);
                }
            } else {
                // Team B strikes
                battalionStates[uint8(Team.A) - 1].soldierCount--;
                if (battalionStates[uint8(Team.A) - 1].soldierCount == 0) {
                    return (battalionStates, true);
                }
            }
        }

        return (battalionStates, isFinished);
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

        require(state.getData(buildingInstance, DATA_BATTLE_START_BLOCK) != bytes32(0), "Base: Battle not started");

        (BattalionState[] memory battalionStates, bool isFinished) = getBattleState(ds, buildingInstance, block.number);

        require(isFinished, "Base: Battle still in play");

        require(
            battalionStates[0].soldierCount > 0 && battalionStates[1].soldierCount > 0,
            "Base: cannot continue a finished battle"
        );

        ds.getDispatcher().dispatch(
            abi.encodeCall(
                Actions.SET_DATA_ON_BUILDING, (buildingInstance, DATA_INIT_STATE, _encodeInitState(battalionStates))
            )
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
