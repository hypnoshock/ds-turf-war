// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {PersonState} from "./LibPerson.sol";

bytes24 constant BASE_BUILDING_KIND = 0xbe92755c0000000000000000a9c1e4010000000000000004;

interface IBase {
    function owner() external returns (address);
    function onConstructLate(Game ds, bytes24 mobileUnitID, bytes24 buildingInstance, bool isInitBase) external;
    function getPersonStates(Game ds, bytes24 buildingInstance, uint256 blockNumber)
        external
        returns (PersonState[] memory);
}
