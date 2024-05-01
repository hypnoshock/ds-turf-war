// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {State} from "cog/IState.sol";

enum GAME_STATE {
    NOT_STARTED,
    IN_PROGRESS,
    FINISHED
}

bytes24 constant HAMMER_ITEM = 0x6a7a67f09e2cd31d00000001000000140000001400000014;

interface IZone {
    function setAreaWinner(Game ds, bytes24 origin, bytes24 player, bool overwrite) external;
    function getGameState(State state, bytes24 zoneID) external view returns (GAME_STATE);
}
