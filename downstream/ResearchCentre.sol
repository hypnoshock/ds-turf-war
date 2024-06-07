// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {State} from "cog/IState.sol";
import {Dispatcher} from "cog/IDispatcher.sol";
import {Schema, Node, CompoundKeyDecoder, BLOCK_TIME_SECS} from "@ds/schema/Schema.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {BuildingKind} from "@ds/ext/BuildingKind.sol";
import {LibString} from "./LibString.sol";
import {LibUtils} from "./LibUtils.sol";
import {IZone, GAME_STATE, DATA_SELECTED_LEVEL, DATA_HAS_CLAIMED_PRIZES, TEAM_A, TEAM_B} from "./IZone.sol";
import {IBase} from "./IBase.sol";
import {LibPerson, PERSON_ITEM, PersonState} from "./LibPerson.sol";
import {LibInventory} from "./LibInventory.sol";

using Schema for State;

uint8 constant SOLDIER_BAG_EQUIP_SLOT = 0;
uint8 constant PERSON_BAG_EQUIP_SLOT = 1;

contract TurfWarsResearchCentre is BuildingKind {
    function addPerson() external {}
    function removePerson(uint16 amount) external {}

    function use(Game ds, bytes24 buildingInstance, bytes24 actor, bytes calldata payload) public override {
        if ((bytes4)(payload) == this.addPerson.selector) {
            _addPerson(ds, buildingInstance, actor);
        } else if ((bytes4)(payload) == this.removePerson.selector) {
            (uint8 amount) = abi.decode(payload[4:], (uint8));
            _removePerson(ds, buildingInstance, actor, amount);
        } else {
            revert("Invalid function selector");
        }
    }

    function _addPerson(Game ds, bytes24 buildingInstance, bytes24 actor) internal {
        // Check that the player transferred enough men to the building
        uint64 amount = LibInventory.getItemBalance(ds.getState(), buildingInstance, PERSON_ITEM, PERSON_BAG_EQUIP_SLOT);

        require(amount > 0, "Base: Must transfer at least one person to the building");

        LibInventory.burnBagContents(ds, buildingInstance, PERSON_BAG_EQUIP_SLOT);
        LibPerson.addPerson(ds, buildingInstance, actor, uint16(amount));
    }

    function _removePerson(Game ds, bytes24 buildingInstance, bytes24 actor, uint16 amount) internal {
        State state = ds.getState();

        require(amount <= 100, "Base: You can only remove up to 100 people at a time");

        LibPerson.removePerson(ds, buildingInstance, actor, amount);

        bytes24 mobileUnitTile = state.getCurrentLocation(actor, uint64(block.number));
        bytes24 zone = Node.Zone(LibUtils.getTileZone(mobileUnitTile));
        IZone zoneImpl = IZone(state.getImplementation(zone));
        zoneImpl.spawnPerson(ds, mobileUnitTile, amount);
    }

    function getPersonStates(Game ds, bytes24 buildingInstance, uint256 blockNumber)
        public
        returns (PersonState[] memory)
    {
        return LibPerson.getPersonStates(ds, buildingInstance, blockNumber);
    }
}
