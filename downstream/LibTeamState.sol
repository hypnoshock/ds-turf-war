// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {State} from "cog/IState.sol";
import {Schema, Node} from "@ds/schema/Schema.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {IZone, GAME_STATE, Team} from "./IZone.sol";

import {LibUtils} from "./LibUtils.sol";

using Schema for State;

struct TeamState {
    bool hasPlacedInitHQ;
}

uint8 constant TEAM_STATE_BIT_LEN = 8;

library LibTeamState {
    function encodeTeamState(TeamState memory teamstate) internal pure returns (uint256) {
        return uint256(uint8(teamstate.hasPlacedInitHQ ? 1 : 0));
    }

    function decodeTeamState(uint256 teamState) internal pure returns (TeamState memory) {
        return TeamState(bool(uint8(teamState) == 1));
    }
}
