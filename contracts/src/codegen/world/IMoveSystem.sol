// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

/* Autogenerated file. Do not edit manually. */

import {PositionData} from "./../index.sol";

/**
 * @title IMoveSystem
 * @author MUD (https://mud.dev) by Lattice (https://lattice.xyz)
 * @dev This interface is automatically generated from the corresponding system contract. Do not edit manually.
 */
interface IMoveSystem {
    function move(bytes32 matchEntity, bytes32 entity, PositionData[] memory path) external;

    function fight(bytes32 matchEntity, bytes32 entity, bytes32 target) external;

    function moveAndAttack(bytes32 matchEntity, bytes32 entity, PositionData[] memory path, bytes32 target) external;
}
