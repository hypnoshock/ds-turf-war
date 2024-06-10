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
    bool hasSlingshot;
    bool hasLongbow;
    bool hasGun;
}

// uint8 constant TEAM_STATE_BIT_LEN = 8;

library LibTeamState {
    function encodeTeamState(TeamState memory teamstate) internal pure returns (uint256) {
        return uint256(
            uint8(teamstate.hasPlacedInitHQ ? 1 : 0) | (uint8(teamstate.hasSlingshot ? 1 : 0) << 1)
                | (uint8(teamstate.hasLongbow ? 1 : 0) << 2) | (uint8(teamstate.hasGun ? 1 : 0) << 3)
        );
    }

    function decodeTeamState(uint256 teamState) internal pure returns (TeamState memory) {
        return TeamState(
            bool(uint8(teamState & 1) == 1),
            bool(uint8((teamState >> 1) & 1) == 1),
            bool(uint8((teamState >> 2) & 1) == 1),
            bool(uint8((teamState >> 3) & 1) == 1)
        );
    }
}
