// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

bytes24 constant BASE_BUILDING_KIND = 0xbe92755c0000000000000000a9c1e4010000000000000004;

interface IBase {
    function owner() external returns (address);
}
