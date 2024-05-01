// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {State} from "cog/IState.sol";

enum GAME_STATE {
    NOT_STARTED,
    IN_PROGRESS,
    FINISHED
}

interface IZone {
    function setAreaWinner(Game ds, bytes24 origin, bytes24 player, bool overwrite) external;
    function getGameState(State state, bytes24 zoneID) external view returns (GAME_STATE);
}
