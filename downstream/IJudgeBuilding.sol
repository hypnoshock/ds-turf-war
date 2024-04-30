// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IBattleBoy} from "./IBattleBoy.sol";

interface IJudgeBuilding {
    function setTileWinner(bytes24 tile, bytes24 player, bytes24 judgeInstance) external;
    function setGame(address game) external;
    function setBattleBuilding(IBattleBoy battleBuilding) external;

    function init(address _owner, address ds, IBattleBoy battleBuilding) external;
}
