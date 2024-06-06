// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {State} from "cog/IState.sol";
import {Schema, Node} from "@ds/schema/Schema.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {IZone, GAME_STATE, Team} from "./IZone.sol";

import {LibUtils} from "./LibUtils.sol";

using Schema for State;

bytes24 constant PERSON_ITEM = 0x6a7a67f05c334a0b000000010000000a0000000a00000028;

library LibPerson {
    function addPerson(Game ds, bytes24 buildingInstance, bytes24 actor, uint8 amount) internal {
        // Does the player have enough people in their inventory?
    }
}
