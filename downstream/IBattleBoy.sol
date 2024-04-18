// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IBattleBoy {
    function setJudgeBuilding(address judgeBuilding) external;
    function setFirstMatchInWindow(bytes32 _firstMatchInWindow) external;
}