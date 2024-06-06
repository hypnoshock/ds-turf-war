// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {State} from "cog/IState.sol";

enum GAME_STATE {
    NOT_STARTED,
    IN_PROGRESS,
    FINISHED
}

enum Team {
    NONE,
    A,
    B
}

bytes24 constant HAMMER_ITEM = 0x6a7a67f09e2cd31d00000001000000140000001400000014;
bytes24 constant PRIZE_ITEM = 0x6a7a67f0ca613996000000010000004b0000000100000001;
string constant DATA_SELECTED_LEVEL = "selectedLevel";
string constant DATA_HAS_CLAIMED_PRIZES = "hasClaimedPrizes";
string constant TEAM_A = "team1";
string constant TEAM_B = "team2";

interface IZone {
    function setAreaWinner(Game ds, bytes24 origin, bytes24 player, bool overwrite) external;
    function getGameState(State state, bytes24 zoneID) external view returns (GAME_STATE);
    function spawnPrizes(Game ds, bytes24 tileID, uint64 count) external;
    function setHasClaimedPrizes(Game ds, bytes24 zoneID) external;
    function burnTileBag(Game ds, bytes24 tile, bytes24 bagID, uint8 equipSlot) external;
    function spawnSoldier(Game ds, bytes24 tileID, uint64 count) external;
    function spawnPerson(Game ds, bytes24 tileID, uint64 count) external;
}
