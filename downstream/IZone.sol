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
bytes24 constant PRIZE_ITEM = 0x6a7a67f0e93f3544000000010000004b0000000100000001;
string constant DATA_SELECTED_LEVEL = "selectedLevel";
string constant DATA_HAS_CLAIMED_PRIZES = "hasClaimedPrizes";
string constant TEAM_A = "teamA";
string constant TEAM_B = "teamB";

interface IZone {
    function setAreaWinner(Game ds, bytes24 origin, bytes24 player, bool overwrite) external;
    function getGameState(State state, bytes24 zoneID) external view returns (GAME_STATE);
    function spawnPrizes(Game ds, bytes24 tileID, uint64 count) external;
    function setHasClaimedPrizes(Game ds, bytes24 zoneID) external;
}
