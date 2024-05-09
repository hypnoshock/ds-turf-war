// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "cog/IGame.sol";
import "cog/IState.sol";
import {ItemKind} from "@ds/ext/ItemKind.sol";
import {Schema, Kind, Node} from "@ds/schema/Schema.sol";

using Schema for State;

contract Trophy is ItemKind {
    function onCraft(Game /*ds*/, bytes24, /*entity*/ bytes24 /*buildingInstanceID*/, bytes24 /*itemID*/, uint64 /*itemQty*/ )
        external
        override
        pure
    {
        revert("TurfWars Trophy: Crafting is not allowed.");
    }

    function onExtract(Game /*ds*/, bytes24, /*entity*/ bytes24 /*buildingInstanceID*/, bytes24 /*itemID*/, uint64 /*itemQty*/ )
        external
        override
        pure
    {
        revert("TurfWars Trophy: Extraction is not allowed.");
    }

    function onSpawn(Game ds, bytes24 zoneOwner, bytes24, /*zoneID*/ bytes24 itemID, uint64 /*itemQty*/ )
        external
        override
    {
        // Can only be spawned in the TurfWars zone
        State state = ds.getState();
        bytes24 itemKind = itemID;
        bytes24 itemKindOwner = state.getOwner(itemKind);
        require(zoneOwner == itemKindOwner, "TurfWars Trophy: Spawning is restricted to TurfWars zone only.");
    }

    function onReward(Game /*ds*/, bytes24, /*winner*/ bytes24 /*sessionID*/, bytes24 /*itemID*/, uint64 /*itemQty*/ )
        external
        override
        pure
    {
        revert("TurfWars Trophy: Reward from combat is not allowed.");
    }
}
