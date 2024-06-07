// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {State} from "cog/IState.sol";
import {Schema, Node} from "@ds/schema/Schema.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {IZone, GAME_STATE, Team} from "./IZone.sol";
import {ABDKMath64x64} from "./libs/ABDKMath64x64.sol";
import {BASE_BUILDING_KIND} from "./IBase.sol";

import {LibUtils} from "./LibUtils.sol";

using Schema for State;

bytes24 constant PERSON_ITEM = 0x6a7a67f0ca70a860000000010000000a000000280000000a;
string constant DATA_PERSON_STATES = "personStates";
string constant DATA_PERSON_STATES_UPDATE_BLOCK = "personStatesUpdateBlock";
uint256 constant POPULATION_INC_PERC_PER_BLOCK = 101;
uint256 constant MAX_ELAPSED_BLOCKS = (60 * 60) / 2; // 1 hour
uint16 constant MAX_POPULATION = 200;

struct PersonState {
    uint8 team;
    uint16 count;
}

uint8 constant PERSON_STATE_BIT_LEN = 8 + 16;

library LibPerson {
    function resetPersonStates(Game ds, bytes24 buildingInstance) internal {
        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, DATA_PERSON_STATES, bytes32(0)))
        );
        // ds.getDispatcher().dispatch(
        //     abi.encodeCall(
        //         Actions.SET_DATA_ON_BUILDING, (buildingInstance, DATA_PERSON_STATES_UPDATE_BLOCK, bytes32(0))
        //     )
        // );
    }

    function addPerson(Game ds, bytes24 buildingInstance, bytes24 actor, uint16 amount) internal {
        State state = ds.getState();

        bytes24 tile = state.getFixedLocation(buildingInstance);
        bytes24 zone = Node.Zone(LibUtils.getTileZone(tile));

        Team team = LibUtils.getUnitTeam(state, zone, actor);

        require(team != Team.NONE, "Base: Player is not in any team");

        bytes32 encodedStates = state.getData(buildingInstance, DATA_PERSON_STATES);
        PersonState[] memory personStates;
        if (encodedStates == bytes32(0)) {
            personStates = new PersonState[](2);
            personStates[0].team = uint8(Team.A);
            personStates[1].team = uint8(Team.B);
        } else {
            personStates = getPersonStates(ds, buildingInstance, block.number);
        }

        personStates[uint8(team) - 1].count += amount;

        ds.getDispatcher().dispatch(
            abi.encodeCall(
                Actions.SET_DATA_ON_BUILDING, (buildingInstance, DATA_PERSON_STATES, _encodePersonStates(personStates))
            )
        );
        ds.getDispatcher().dispatch(
            abi.encodeCall(
                Actions.SET_DATA_ON_BUILDING, (buildingInstance, DATA_PERSON_STATES_UPDATE_BLOCK, bytes32(block.number))
            )
        );
    }

    function removePerson(Game ds, bytes24 buildingInstance, bytes24 actor, uint16 amount) internal {
        State state = ds.getState();

        bytes24 tile = state.getFixedLocation(buildingInstance);
        bytes24 zone = Node.Zone(LibUtils.getTileZone(tile));

        Team team = LibUtils.getUnitTeam(state, zone, actor);

        require(team != Team.NONE, "Base: Player is not in any team");

        bytes32 encodedStates = state.getData(buildingInstance, DATA_PERSON_STATES);
        PersonState[] memory personStates = getPersonStates(ds, buildingInstance, block.number);

        require(personStates[uint8(team) - 1].count >= amount, "Base: Not enough people to remove");

        personStates[uint8(team) - 1].count -= amount;

        ds.getDispatcher().dispatch(
            abi.encodeCall(
                Actions.SET_DATA_ON_BUILDING, (buildingInstance, DATA_PERSON_STATES, _encodePersonStates(personStates))
            )
        );
        ds.getDispatcher().dispatch(
            abi.encodeCall(
                Actions.SET_DATA_ON_BUILDING, (buildingInstance, DATA_PERSON_STATES_UPDATE_BLOCK, bytes32(block.number))
            )
        );
    }

    function getPersonStates(Game ds, bytes24 buildingInstance, uint256 blockNumber)
        internal
        returns (PersonState[] memory)
    {
        State state = ds.getState();

        bytes32 encodedStates = state.getData(buildingInstance, DATA_PERSON_STATES);
        uint256 updateBlock = uint256(state.getData(buildingInstance, DATA_PERSON_STATES_UPDATE_BLOCK));
        if (encodedStates == bytes32(0) || updateBlock == 0) {
            return new PersonState[](2);
        }

        PersonState[] memory personStates = _decodePersonStates(encodedStates);

        // Only increase population on base buildings
        if (state.getBuildingKind(buildingInstance) != BASE_BUILDING_KIND) {
            return personStates;
        }

        uint256 elapsedBlocks = (block.number - updateBlock) / 2; // We'll update the population every 2 blocks
        if (elapsedBlocks > MAX_ELAPSED_BLOCKS) {
            elapsedBlocks = MAX_ELAPSED_BLOCKS;
        }

        // result of this is signed 64.64-bit fixed point number
        int128 factor = ABDKMath64x64.pow(ABDKMath64x64.divu(POPULATION_INC_PERC_PER_BLOCK, 100), elapsedBlocks);

        for (uint8 i = 0; i < personStates.length; i++) {
            if (personStates[i].count == 0) {
                continue;
            }
            uint256 newCount = ABDKMath64x64.mulu(factor, uint64(personStates[i].count));
            if (newCount > MAX_POPULATION) {
                personStates[i].count = MAX_POPULATION;
            } else {
                personStates[i].count = uint16(newCount);
            }
        }

        return personStates;
    }

    function _encodePersonStates(PersonState[] memory states) internal pure returns (bytes32) {
        bytes32 encodedStates = bytes32(states.length);
        for (uint256 i = 0; i < states.length; i++) {
            uint256 encodedState = _encodePersonState(states[i]);
            encodedStates |= bytes32(encodedState << (8 + (PERSON_STATE_BIT_LEN * i)));
        }
        return encodedStates;
    }

    function _decodePersonStates(bytes32 encodedStates) internal pure returns (PersonState[] memory) {
        uint8 length = uint8(uint256(encodedStates) & 0xff);
        PersonState[] memory states = new PersonState[](length);
        for (uint8 i = 0; i < length; i++) {
            uint256 encodedState = uint256(encodedStates >> (8 + (PERSON_STATE_BIT_LEN * i)));
            states[i] = _decodePersonState(encodedState);
        }
        return states;
    }

    function _encodePersonState(PersonState memory state) internal pure returns (uint256) {
        uint256 encodedState = uint256(state.team) | uint256(state.count) << 16;
        return encodedState;
    }

    function _decodePersonState(uint256 encodedState) internal pure returns (PersonState memory state) {
        state.team = uint8(encodedState & 0xff);
        state.count = uint8((encodedState >> 16) & 0xffff);
    }
}
