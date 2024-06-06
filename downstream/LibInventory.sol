// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {Dispatcher} from "cog/IDispatcher.sol";
import {State} from "cog/IState.sol";
import {Schema, Node} from "@ds/schema/Schema.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {IZone, GAME_STATE, Team} from "./IZone.sol";

import {LibUtils} from "./LibUtils.sol";

using Schema for State;

uint8 constant TEMP_BAG_EQUIP_SLOT = 100;

library LibInventory {
    function hasItem(State state, bytes24 entityID, bytes24 itemID, uint64 quantity, uint8 equipIndex)
        internal
        view
        returns (bool)
    {
        uint64 itemTotal = 0;
        bytes24 bagID = state.getEquipSlot(entityID, equipIndex);
        if (bagID == 0) {
            return false;
        }
        for (uint8 slotIndex = 0; slotIndex < 4; slotIndex++) {
            (bytes24 inventoryItem, uint64 inventoryBalance) = state.getItemSlot(bagID, slotIndex);
            if (inventoryItem == itemID) {
                if (inventoryBalance >= quantity) {
                    return true;
                } else {
                    itemTotal += inventoryBalance;
                    if (itemTotal >= quantity) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    function hasItem(State state, bytes24 entityID, bytes24 itemID, uint64 quantity) internal view returns (bool) {
        uint64 itemTotal = 0;
        for (uint8 equipIndex = 0; equipIndex < 2; equipIndex++) {
            bytes24 bagID = state.getEquipSlot(entityID, equipIndex);
            if (bagID == 0) {
                continue;
            }
            for (uint8 slotIndex = 0; slotIndex < 4; slotIndex++) {
                (bytes24 inventoryItem, uint64 inventoryBalance) = state.getItemSlot(bagID, slotIndex);
                if (inventoryItem == itemID) {
                    if (inventoryBalance >= quantity) {
                        return true;
                    } else {
                        itemTotal += inventoryBalance;
                        if (itemTotal >= quantity) {
                            return true;
                        }
                    }
                }
            }
        }
        return false;
    }

    function getItemBalance(State state, bytes24 entityID, bytes24 itemID) internal view returns (uint64) {
        uint64 itemTotal = 0;
        for (uint8 equipIndex = 0; equipIndex < 2; equipIndex++) {
            bytes24 unitBag = state.getEquipSlot(entityID, equipIndex);
            if (unitBag == 0) {
                continue;
            }
            for (uint8 slotIndex = 0; slotIndex < 4; slotIndex++) {
                (bytes24 inventoryItem, uint64 inventoryBalance) = state.getItemSlot(unitBag, slotIndex);
                if (inventoryItem == itemID) {
                    itemTotal += inventoryBalance;
                }
            }
        }
        return itemTotal;
    }

    function getItemBalance(State state, bytes24 entityID, bytes24 itemID, uint8 equipIndex)
        internal
        view
        returns (uint64)
    {
        bytes24 unitBag = state.getEquipSlot(entityID, equipIndex);
        if (unitBag == 0) {
            return 0;
        }

        uint64 itemTotal = 0;
        for (uint8 slotIndex = 0; slotIndex < 4; slotIndex++) {
            (bytes24 inventoryItem, uint64 inventoryBalance) = state.getItemSlot(unitBag, slotIndex);
            if (inventoryItem == itemID) {
                itemTotal += inventoryBalance;
            }
        }
        return itemTotal;
    }

    // Transfers the bag to the tile, burns it and creates a new empty bag in place of the burnt bag
    function burnBagContents(Game ds, bytes24 buildingInstance, uint8 equipSlot) internal {
        State state = ds.getState();
        Dispatcher dispatcher = ds.getDispatcher();

        bytes24 tile = state.getFixedLocation(buildingInstance);
        bytes24 buildingBag = state.getEquipSlot(buildingInstance, equipSlot);

        // Transfer bag to tile (zone can only destroy tile bags)
        // function TRANSFER_BAG(bytes24 bag, bytes24 fromEntity, bytes24 toEntity, uint8 toEquipSlot) external;
        dispatcher.dispatch(
            abi.encodeCall(Actions.TRANSFER_BAG, (buildingBag, buildingInstance, tile, TEMP_BAG_EQUIP_SLOT))
        );

        // Burn bag
        bytes24 zone = Node.Zone(LibUtils.getTileZone(tile));
        IZone zoneImpl = IZone(state.getImplementation(zone));
        zoneImpl.burnTileBag(ds, tile, buildingBag, TEMP_BAG_EQUIP_SLOT);

        // Create new bag
        // SPAWN_EMPTY_BAG(bytes24 equipee, uint8 equipSlot)
        dispatcher.dispatch(abi.encodeCall(Actions.SPAWN_EMPTY_BAG, (buildingInstance, equipSlot)));
    }
}
