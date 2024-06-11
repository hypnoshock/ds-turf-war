// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {State} from "cog/IState.sol";
import {Schema, Node, CompoundKeyDecoder, BLOCK_TIME_SECS} from "@ds/schema/Schema.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {BuildingKind} from "@ds/ext/BuildingKind.sol";
import {LibString} from "./LibString.sol";
import {LibUtils} from "./LibUtils.sol";
import {IZone, GAME_STATE, DATA_SELECTED_LEVEL, Team} from "./IZone.sol";
import {IBase} from "./IBase.sol";
import {
    LibCombat,
    Weapon,
    BattalionState,
    DATA_INIT_STATE,
    NUM_WEAPON_KINDS,
    NUM_DEFENCE_LEVELS,
    SOLDIER_ITEM
} from "./LibCombat.sol";
import {LibPerson, PERSON_ITEM, PersonState} from "./LibPerson.sol";
import {LibInventory} from "./LibInventory.sol";

using Schema for State;

uint8 constant SOLDIER_BAG_EQUIP_SLOT = 0;
uint8 constant WEAPON_BAG_EQUIP_SLOT = 1;
uint8 constant PERSON_BAG_EQUIP_SLOT = 1;

contract Base is BuildingKind, IBase {
    function startBattle() external {}
    function continueBattle() external {}
    function claimWin() external {}

    function addSoldiers(uint8 amount) external {}
    function removeSoldiers(uint64 amount) external {}
    function addPerson() external {}
    function removePerson(uint16 amount) external {}

    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Base: Only owner can call this function");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function use(Game ds, bytes24 buildingInstance, bytes24 actor, bytes calldata payload) public override {
        if ((bytes4)(payload) == this.startBattle.selector) {
            _startBattle(ds, buildingInstance);
        } else if ((bytes4)(payload) == this.claimWin.selector) {
            _claimWin(ds, buildingInstance, actor);
        } else if ((bytes4)(payload) == this.addPerson.selector) {
            _addPerson(ds, buildingInstance, actor);
        } else if ((bytes4)(payload) == this.removePerson.selector) {
            (uint8 amount) = abi.decode(payload[4:], (uint8));
            _removePerson(ds, buildingInstance, actor, amount);
        } else if ((bytes4)(payload) == this.addSoldiers.selector) {
            (uint8 amount) = abi.decode(payload[4:], (uint8));
            _addSoldiers(ds, buildingInstance, actor, amount);
        } else if ((bytes4)(payload) == this.continueBattle.selector) {
            LibCombat.continueBattle(ds, buildingInstance);
        } else {
            revert("Invalid function selector");
        }
    }

    function _startBattle(Game ds, bytes24 buildingInstance) internal {
        // NOTE: This check can be deleted if we go over the contract size limit. Just check in frontend and don't worry about cheating
        (BattalionState[] memory battalionStates, /*bool isFinished*/ ) =
            LibCombat.getBattleState(ds, buildingInstance, block.number);

        // TODO: Battle can be started if attackers are > 0
        // Get tile team
        // If at least one team that isn't the tile team has soldiers, start battle
        uint8 readyTeams = 0;
        for (uint8 i = 0; i < battalionStates.length; i++) {
            if (battalionStates[i].soldierCount > 0) {
                readyTeams++;
            }
        }
        require(readyTeams > 1, "Base: At least 2 teams must have soldiers to start battle");

        LibCombat.startBattle(ds, buildingInstance);
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

    function _addSoldiers(Game ds, bytes24 buildingInstance, bytes24 actor, uint8 amount) internal {
        State state = ds.getState();

        // Check that the player transferred enough men to the building
        require(
            LibInventory.hasItem(ds.getState(), buildingInstance, SOLDIER_ITEM, amount, SOLDIER_BAG_EQUIP_SLOT),
            "Base: Not enough soldiers transferred to building"
        );

        LibInventory.burnBagContents(ds, buildingInstance, SOLDIER_BAG_EQUIP_SLOT);

        // Add weapons
        uint8 unarmedSoldiers = amount;
        uint8[NUM_WEAPON_KINDS] memory weapons;
        uint8[NUM_DEFENCE_LEVELS] memory defence;
        bytes24 weaponBag = state.getEquipSlot(buildingInstance, WEAPON_BAG_EQUIP_SLOT);
        for (uint8 i = 0; i < 4; i++) {
            (bytes24 weaponItem, uint64 weaponBalance) = state.getItemSlot(weaponBag, i);
            if (weaponItem == bytes24(0) || weaponBalance == 0) {
                continue;
            }

            Weapon weapon = LibCombat.getWeaponKind(weaponItem);
            if (weapon == Weapon.None) {
                continue;
            }

            weapons[uint8(weapon)] += uint8(weaponBalance);
            unarmedSoldiers -= uint8(weaponBalance);
        }

        weapons[0] += unarmedSoldiers;
        LibInventory.burnBagContents(ds, buildingInstance, WEAPON_BAG_EQUIP_SLOT);

        unarmedSoldiers = amount;
        for (uint8 j = 0; j < NUM_DEFENCE_LEVELS; j++) {
            unarmedSoldiers -= defence[j];
        }
        defence[0] += unarmedSoldiers;

        LibCombat.addSoldiers(ds, buildingInstance, actor, amount, weapons, defence);
    }

    // -- Hooks

    function construct(Game ds, bytes24, /*buildingKind*/ bytes24 mobileUnitID, bytes memory coordsEncoded)
        public
        override
    {
        State state = ds.getState();

        // NOTE: Cannot set data in construct hook because it's fired off before owner set

        int16[4] memory coords = abi.decode(coordsEncoded, (int16[4]));
        bytes24 zone = Node.Zone(coords[0]);
        IZone zoneImpl = IZone(state.getImplementation(zone));
        require(address(zoneImpl) != address(0), "Base::construct - No implementation for zone");
        zoneImpl.setAreaWinner(ds, Node.Tile(coords[0], coords[1], coords[2], coords[3]), mobileUnitID, false);
    }

    function _claimWin(Game ds, bytes24 buildingInstance, bytes24 actor) internal {
        State state = ds.getState();

        bytes24 tile = state.getFixedLocation(buildingInstance);

        (BattalionState[] memory battalionStates, bool isFinished) =
            LibCombat.getBattleState(ds, buildingInstance, block.number);

        require(isFinished, "Battle not finished yet");
        require(
            battalionStates[0].soldierCount == 0 || battalionStates[1].soldierCount == 0, "Base: Battle is not finished"
        );

        bytes24 zone = Node.Zone(LibUtils.getTileZone(tile));
        Team playerTeam = LibUtils.getUnitTeam(state, zone, actor);
        Team tileTeam = LibUtils.getTileTeam(state, zone, tile);
        Team winningTeam = battalionStates[0].soldierCount == 0 ? Team.B : Team.A;

        // TODO: Either side should be able to end the battle but for that to work, we need to save teams to tiles instead of mobile unit IDs
        require(playerTeam == winningTeam, "Base: Player is not in the winning team");

        LibCombat.resetStartBlock(ds, buildingInstance);

        // If the defenders won, set the resultant state as init state
        LibCombat.setInitState(ds, buildingInstance, battalionStates);
        if (tileTeam != winningTeam) {
            IZone zoneImpl = IZone(state.getImplementation(zone));
            zoneImpl.setAreaWinner(ds, tile, actor, true);
            // zoneImpl.spawnSoldier(ds, tile, battalionStates[uint8(winningTeam) - 1].soldierCount);
        }
    }

    function zoneAddPerson(Game ds, bytes24 mobileUnitID, bytes24 buildingInstance, uint16 amount) public {
        State state = ds.getState();

        // Only callable from zone contract
        bytes24 zone = Node.Zone(LibUtils.getTileZone(state.getFixedLocation(buildingInstance)));
        IZone zoneImpl = IZone(state.getImplementation(zone));
        require(msg.sender == address(zoneImpl), "Base: Only zone contract can call this function");

        LibPerson.addPerson(ds, buildingInstance, mobileUnitID, amount);
    }

    function getBattleState(Game ds, bytes24 buildingInstance, uint256 blockNumber)
        public
        returns (BattalionState[] memory battalionStates, bool isFinished)
    {
        return LibCombat.getBattleState(ds, buildingInstance, blockNumber);
    }

    function getPersonStates(Game ds, bytes24 buildingInstance, uint256 blockNumber)
        public
        returns (PersonState[] memory)
    {
        return LibPerson.getPersonStates(ds, buildingInstance, blockNumber);
    }
}
