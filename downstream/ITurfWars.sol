// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ITurfWars {
    function getWinningPlayer(bytes32 matchEntity) external view returns (bytes32);
    function isAddressWinner(address playerAddress, bytes32 matchEntity) external view returns (bool);
    function startBattle(string memory name, bytes32 firstMatchInWindow, bytes32 matchID, bytes32 level) external;
    function hasAnyPlayerJoinedMatch(bytes32 matchEntity) external view returns (bool);
}
