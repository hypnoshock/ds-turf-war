// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IJudgeBuilding {
    function setTileWinner(bytes24 tile, bytes24 player, bytes24 judgeInstance) external;
    function setGame(address game) external;
    function setBuildingInstance(bytes24 buildingInstance) external;
}