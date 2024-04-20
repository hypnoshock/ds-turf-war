// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ITurfWars } from "./ITurfWars.sol";

interface IBattleBoy {
    function init(
        address _owner,
        address _judgeBuilding,
        address _skyStrifeWorld,
        address _turfWars,
        bytes32 _firstMatchInWindow
    ) external;

    function setJudgeBuilding(address judgeBuilding) external;
    function setFirstMatchInWindow(bytes32 _firstMatchInWindow) external;
    function setSkyStrifeWorld(address _world) external;
    function setTurfWars(address _turfWars) external;

    function turfWars() view external returns (ITurfWars);
}