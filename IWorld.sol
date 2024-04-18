// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IWorld {
  function test() external pure returns (uint256);

  function createMatch(
    string memory name,
    bytes32 claimedFirstMatchInWindow,
    bytes32 matchEntity,
    bytes32 levelId
  ) external;

  function copyMap(bytes32 matchEntity) external;
  function buySeasonPass(address account) external payable;

}