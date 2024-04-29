// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";

interface IZone {
   function setAreaWinner(Game ds, bytes24 origin, bytes24 player, bool overwrite)  external;
}