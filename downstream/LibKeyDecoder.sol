// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library CompoundKeyDecoder {
    function UINT64(bytes24 id) internal pure returns (uint64) {
        return uint64(uint192(id));
    }

    function BYTES8(bytes24 id) internal pure returns (bytes8) {
        return bytes8(uint64(uint192(id)));
    }

    function UINT8_ARRAY(bytes24 id) internal pure returns (uint8[8] memory keys) {
        keys[0] = uint8(uint192(id) >> 56);
        keys[1] = uint8(uint192(id) >> 48);
        keys[2] = uint8(uint192(id) >> 40);
        keys[3] = uint8(uint192(id) >> 32);
        keys[4] = uint8(uint192(id) >> 24);
        keys[5] = uint8(uint192(id) >> 16);
        keys[6] = uint8(uint192(id) >> 8);
        keys[7] = uint8(uint192(id));
    }

    function UINT16_ARRAY(bytes24 id) internal pure returns (uint16[4] memory keys) {
        keys[0] = uint16(uint192(id) >> 48);
        keys[1] = uint16(uint192(id) >> 32);
        keys[2] = uint16(uint192(id) >> 16);
        keys[3] = uint16(uint192(id));
    }

    function INT16_ARRAY(bytes24 id) internal pure returns (int16[4] memory keys) {
        keys[0] = int16(int192(uint192(id) >> 48));
        keys[1] = int16(int192(uint192(id) >> 32));
        keys[2] = int16(int192(uint192(id) >> 16));
        keys[3] = int16(int192(uint192(id)));
    }

    function UINT32_ARRAY(bytes24 id) internal pure returns (uint32[2] memory keys) {
        keys[0] = uint32(uint192(id) >> 32);
        keys[1] = uint32(uint192(id));
    }

    function INT32_ARRAY(bytes24 id) internal pure returns (int32[2] memory keys) {
        keys[0] = int32(int192(uint192(id) >> 32));
        keys[1] = int32(int192(uint192(id)));
    }

    function ADDRESS(bytes24 id) internal pure returns (address) {
        return address(uint160(uint192(id)));
    }

    function STRING(bytes24 id) internal pure returns (string memory) {
        // Find string length. Keys are fixed at 20 bytes so treat first 0 as null terminator
        uint8 len;
        while (len < 20 && id[4 + len] != 0) {
            len++;
        }

        // Copy string bytes
        bytes memory stringBytes = new bytes(len);
        for (uint8 i = 0; i < len; i++) {
            stringBytes[i] = id[4 + i];
        }

        return string(stringBytes);
    }
}
