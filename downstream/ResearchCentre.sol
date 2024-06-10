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
import {IZone, GAME_STATE, DATA_SELECTED_LEVEL, DATA_HAS_CLAIMED_PRIZES, Team, TEAM_A, TEAM_B} from "./IZone.sol";
import {IBase} from "./IBase.sol";
import {LibPerson, PERSON_ITEM, PersonState} from "./LibPerson.sol";
import {LibInventory} from "./LibInventory.sol";
import {Weapon} from "./LibCombat.sol";

import {ABDKMath64x64} from "./libs/ABDKMath64x64.sol";

using Schema for State;
using ABDKMath64x64 for int128;

uint256 constant MAX_ELAPSED_BLOCKS = (60 * 60) / 2; // 1 hour

uint8 constant SOLDIER_BAG_EQUIP_SLOT = 0;
uint8 constant PERSON_BAG_EQUIP_SLOT = 1;

string constant DATA_RESEARCHED_TECH = "researchedTech";
string constant DATA_RESEARCH_UPDATE_BLOCK = "researchUpdateBlock";
string constant DATA_RESEARCH_PERC = "researchPerc";

contract TurfWarsResearchCentre is BuildingKind {
    function addPerson() external {}
    function removePerson(uint16 amount) external {}
    function setResearchedTech(uint8 tech) external {}

    function use(Game ds, bytes24 buildingInstance, bytes24 actor, bytes calldata payload) public override {
        if ((bytes4)(payload) == this.addPerson.selector) {
            _addPerson(ds, buildingInstance, actor);
        } else if ((bytes4)(payload) == this.removePerson.selector) {
            (uint8 amount) = abi.decode(payload[4:], (uint8));
            _removePerson(ds, buildingInstance, actor, amount);
        } else if ((bytes4)(payload) == this.setResearchedTech.selector) {
            (uint8 researchedTech) = abi.decode(payload[4:], (uint8));
            _setResearchedTech(ds, buildingInstance, Weapon(researchedTech));
        } else {
            revert("Invalid function selector");
        }
    }

    function _setResearchedTech(Game ds, bytes24 buildingInstance, Weapon researchedTech) internal {
        require(researchedTech != Weapon.None, "ResearchCentre: Must select a valid tech to research");

        // Check that the player transferred
        _setData(ds, buildingInstance, DATA_RESEARCHED_TECH, uint256(researchedTech));
        _setData(ds, buildingInstance, DATA_RESEARCH_UPDATE_BLOCK, block.number);
        _setData(ds, buildingInstance, DATA_RESEARCH_PERC, uint256(0));
    }

    function _addPerson(Game ds, bytes24 buildingInstance, bytes24 actor) internal {
        _updateResearchState(ds, buildingInstance);

        // Check that the player transferred enough men to the building
        uint64 amount = LibInventory.getItemBalance(ds.getState(), buildingInstance, PERSON_ITEM, PERSON_BAG_EQUIP_SLOT);

        require(amount > 0, "ResearchCentre: Must transfer at least one person to the building");

        LibInventory.burnBagContents(ds, buildingInstance, PERSON_BAG_EQUIP_SLOT);
        LibPerson.addPerson(ds, buildingInstance, actor, uint16(amount));
    }

    function _removePerson(Game ds, bytes24 buildingInstance, bytes24 actor, uint16 amount) internal {
        _updateResearchState(ds, buildingInstance);

        State state = ds.getState();

        require(amount <= 100, "ResearchCentre: You can only remove up to 100 people at a time");

        LibPerson.removePerson(ds, buildingInstance, actor, amount);

        bytes24 mobileUnitTile = state.getCurrentLocation(actor, uint64(block.number));
        bytes24 zone = Node.Zone(LibUtils.getTileZone(mobileUnitTile));
        IZone zoneImpl = IZone(state.getImplementation(zone));
        zoneImpl.spawnPerson(ds, mobileUnitTile, amount);
    }

    function _updateResearchState(Game ds, bytes24 buildingInstance) internal {
        (Weapon researchedTech, int128 researchPerc) = getResearchState(ds, buildingInstance);

        if (researchedTech == Weapon.None) {
            return;
        }

        if (researchPerc == ABDKMath64x64.fromUInt(100)) {
            _setData(ds, buildingInstance, DATA_RESEARCHED_TECH, uint256(Weapon.None));
            _setData(ds, buildingInstance, DATA_RESEARCH_UPDATE_BLOCK, uint256(0));
            _setData(ds, buildingInstance, DATA_RESEARCH_PERC, uint256(0));

            // Give the player the researched tech either blueprint item to build factory or set flag to allow building
            State state = ds.getState();
            bytes24 tile = state.getFixedLocation(buildingInstance);
            bytes24 zoneID = Node.Zone(LibUtils.getTileZone(tile));
            Team team = LibUtils.getTileTeam(state, zoneID, tile);

            IZone zoneImpl = IZone(state.getImplementation(zoneID));
            zoneImpl.awardBlueprint(ds, zoneID, researchedTech, team);
        } else {
            _setData(ds, buildingInstance, DATA_RESEARCH_PERC, uint256(int256(researchPerc)));
            _setData(ds, buildingInstance, DATA_RESEARCH_UPDATE_BLOCK, uint256(block.number));
        }
    }

    function getResearchState(Game ds, bytes24 buildingInstance)
        public
        returns (Weapon researchedTech, int128 researchPerc)
    {
        State state = ds.getState();

        // Get number of scientists in the building
        PersonState[] memory personStates = getPersonStates(ds, buildingInstance, block.number);
        uint16 personCount;
        for (uint8 i = 0; i < personStates.length; i++) {
            personCount += personStates[i].count;
        }

        if (personCount == 0) {
            return (Weapon.None, ABDKMath64x64.fromUInt(0));
        }

        researchedTech = Weapon(uint256(state.getData(buildingInstance, DATA_RESEARCHED_TECH)));
        if (researchedTech == Weapon.None) {
            return (Weapon.None, ABDKMath64x64.fromUInt(0));
        }

        uint256 lastUpdateBlock = uint256(state.getData(buildingInstance, DATA_RESEARCH_UPDATE_BLOCK));
        if (lastUpdateBlock == 0) {
            return (Weapon.None, ABDKMath64x64.fromUInt(0));
        }

        researchPerc = int128(int256(uint256(state.getData(buildingInstance, DATA_RESEARCH_PERC))));

        uint256 elapsedBlocks = block.number - lastUpdateBlock;
        if (elapsedBlocks > MAX_ELAPSED_BLOCKS) {
            elapsedBlocks = MAX_ELAPSED_BLOCKS;
        }

        int128 newResearchPerc = researchPerc
            + _getTechIncPercPerPerson(researchedTech).mul(ABDKMath64x64.fromUInt(elapsedBlocks)).mul(
                ABDKMath64x64.fromUInt(personCount)
            );

        if (newResearchPerc > ABDKMath64x64.fromUInt(100)) {
            newResearchPerc = ABDKMath64x64.fromUInt(100);
        }

        return (researchedTech, newResearchPerc);
    }

    function _getTechIncPercPerPerson(Weapon researchedTech) private pure returns (int128) {
        if (researchedTech == Weapon.Slingshot) {
            return ABDKMath64x64.divu(10, 100);
        } else if (researchedTech == Weapon.Longbow) {
            return ABDKMath64x64.divu(3, 100);
        } else if (researchedTech == Weapon.Gun) {
            return ABDKMath64x64.divu(1, 100);
        }

        return ABDKMath64x64.fromUInt(0);
    }

    function getPersonStates(Game ds, bytes24 buildingInstance, uint256 blockNumber)
        public
        returns (PersonState[] memory)
    {
        return LibPerson.getPersonStates(ds, buildingInstance, blockNumber);
    }

    function _setData(Game ds, bytes24 buildingInstance, string memory key, bytes32 value) private {
        ds.getDispatcher().dispatch(abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, key, value)));
    }

    function _setData(Game ds, bytes24 buildingInstance, string memory key, uint256 value) private {
        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, key, bytes32(value)))
        );
    }
}
