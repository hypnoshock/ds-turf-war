// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { MatchIndexToEntity, MatchSky } from "./codegen/index.sol";

library Helper {
    function findFirstMatchInWindow(uint256 window) internal view returns (bytes32) {
        uint256 windowStart = block.timestamp > window ? block.timestamp - window : 0;
        uint256 maxTimestamp = block.timestamp;
        uint32 matchIndex = 1;
        bytes32 matchEntity = bytes32(uint256(1));
        bytes32 foundMatch;

        while (matchEntity != 0) {
            matchEntity = MatchIndexToEntity.get(matchIndex);

            if (MatchSky.getCreatedAt(matchEntity) >= windowStart && MatchSky.getCreatedAt(matchEntity) < maxTimestamp) {
                foundMatch = matchEntity;
                maxTimestamp = MatchSky.getCreatedAt(matchEntity);
            }
            matchIndex++;
        }

        return foundMatch;
    }
}