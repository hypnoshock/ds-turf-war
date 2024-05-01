// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {CompoundKeyDecoder} from "cog/IState.sol";
import {LibString} from "./LibString.sol";

library LibUtils {
    function getTileMatchKey(bytes24 tile) internal pure returns (string memory) {
        return string(abi.encodePacked(LibString.toHexString(uint192(bytes24(tile)), 24), "_entityID"));
    }

    function getTileWinnerKey(bytes24 tile) internal pure returns (string memory) {
        return string(abi.encodePacked(LibString.toHexString(uint192(bytes24(tile)), 24), "_winner"));
    }

    function getTileMatchTimeoutBlockKey(bytes24 tile) internal pure returns (string memory) {
        return string(abi.encodePacked(LibString.toHexString(uint192(bytes24(tile)), 24), "_matchTimeoutBlock"));
    }

    function getTileCoords(bytes24 tile) internal pure returns (int16 z, int16 q, int16 r, int16 s) {
        int16[4] memory keys = CompoundKeyDecoder.INT16_ARRAY(tile);
        return (keys[0], keys[1], keys[2], keys[3]);
    }
}
