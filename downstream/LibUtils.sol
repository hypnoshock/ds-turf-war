// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {State, CompoundKeyDecoder} from "cog/IState.sol";
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

    function isUnitInTeam(State state, bytes24 zoneID, string memory teamPrefix, bytes24 unitId)
        internal
        view
        returns (bool)
    {
        uint64 teamLength = uint64(uint256(state.getData(zoneID, string(abi.encodePacked(teamPrefix, "Length")))));
        // check every slot for unit id
        for (uint64 i = 0; i < teamLength; i++) {
            string memory teamUnitIndex = string(abi.encodePacked(teamPrefix, "Unit_", LibString.toString(i)));
            if (bytes24(state.getData(zoneID, teamUnitIndex)) == unitId) {
                return true;
            }
        }
        return false;
    }
}
