// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {State} from "cog/IState.sol";
import {Schema, Node} from "@ds/schema/Schema.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {IZone, GAME_STATE, Team} from "./IZone.sol";

import {LibUtils} from "./LibUtils.sol";

using Schema for State;

bytes24 constant PERSON_ITEM = 0x6a7a67f0ca70a860000000010000000a000000280000000a;
string constant DATA_PERSON_STATES = "personStates";

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
            personStates = _decodePersonStates(encodedStates);
        }

        personStates[uint8(team) - 1].count += amount;

        ds.getDispatcher().dispatch(
            abi.encodeCall(
                Actions.SET_DATA_ON_BUILDING, (buildingInstance, DATA_PERSON_STATES, _encodePersonStates(personStates))
            )
        );
    }

    function getPersonStates(Game ds, bytes24 buildingInstance, uint256 blockNumber)
        internal
        returns (PersonState[] memory)
    {
        State state = ds.getState();

        bytes32 encodedStates = state.getData(buildingInstance, DATA_PERSON_STATES);
        if (encodedStates == bytes32(0)) {
            return new PersonState[](2);
        }

        return _decodePersonStates(encodedStates);
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
