// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {State} from "cog/IState.sol";
import {Schema} from "@ds/schema/Schema.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {BuildingKind} from "@ds/ext/BuildingKind.sol";
import {IWorld} from "./IWorld.sol";
import {LibString} from "./LibString.sol";

using Schema for State;

contract BattleBoy is BuildingKind {
    address constant WORLD_CONTRACT_ADDR = 0x46B80846B0A65849d689e6402a365cec49B648B6;

    bytes32 constant LEVEL_FOUR_PLAYER = 0x4361756c64726f6e2d3200000000000000000000000000000000000000000000;
    bytes32 constant LEVEL_KNIFE_FIGHT = 0x4b6e6966655f46696768745f3200000000000000000000000000000000000000;
    bytes32 constant FIRST_MATCH_IN_WINDOW = 0x568fbbea00000000000000000000000000000000000000000000000000000000; // param after name
    bytes32 constant HERO = 0x48616c6265726469657200000000000000000000000000000000000000000000;

    function buySeasonPass() external {}
    function startWar() external {}

    function use(Game ds, bytes24 buildingInstance, bytes24, /*actor*/ bytes memory payload ) public override {
        if ((bytes4)(payload) == this.buySeasonPass.selector) {
            _buySeasonPass(ds, buildingInstance);
        } else if ((bytes4)(payload) == this.startWar.selector) {
            _startWar(ds, buildingInstance);
        } 
    }

    function _buySeasonPass(Game ds, bytes24 buildingInstance) internal {
        State state = ds.getState();

        uint256 hasPass = uint256(state.getData(buildingInstance, "hasPass"));
        require(hasPass == 1, "Season pass already purchased");

        IWorld world = IWorld(WORLD_CONTRACT_ADDR);
        world.buySeasonPass{value: 0.01 ether}(address(this));

        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, "hasPass", bytes32(uint256(1))))
        );
    }

    function _startWar(Game ds, bytes24 buildingInstance) internal {
        State state = ds.getState();

        IWorld world = IWorld(WORLD_CONTRACT_ADDR);
        
        uint256 count = uint256(state.getData(buildingInstance, "count")) + 1;
        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, "count", bytes32(count)))
        );
        string memory name = string(abi.encodePacked("Downstream_", LibString.toString(uint256(count))));

        bytes32 claimedFirstMatchInWindow = FIRST_MATCH_IN_WINDOW;
        bytes32 entityID = _getEntityID(ds, buildingInstance); // bytes32(0x153038b100000000000000000000000000000000000000000000000000000000);

        world.createMatch(name, claimedFirstMatchInWindow, entityID, LEVEL_FOUR_PLAYER);
        world.copyMap(entityID);

        // Join the match (Can't do this... as the building would be joining the war)
        // world.register(entityID, 0, HERO);
    }

    // function _joinWar(Game ds, bytes24 buildingInstance) internal {
    //     State state = ds.getState();

    //     IWorld world = IWorld(0x46B80846B0A65849d689e6402a365cec49B648B6);
        
    //     uint256 count = uint256(state.getData(buildingInstance, "count")) + 1;
    //     ds.getDispatcher().dispatch(
    //         abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, "count", bytes32(count)))
    //     );
    //     string memory name = string(abi.encodePacked("Downstream_", LibString.toString(uint256(count))));

    //     bytes32 claimedFirstMatchInWindow = FIRST_MATCH_IN_WINDOW;
    //     bytes32 entityID = _getEntityID(ds, buildingInstance); // bytes32(0x153038b100
    // }

//////////////////////////////////////// SHITE BELOW ////////////////////////////////////////

    function _getEntityID(Game ds, bytes24 buildingInstance) internal returns (bytes32) {
        State state = ds.getState();

        uint256 entityID = uint256(state.getData(buildingInstance, "prevEntityID"));
        if (entityID == 0) {
            entityID = 0x153038b100000000000000000000000000000000000000000000000000000000;
        } else {
            entityID += 1;
        }

        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, "prevEntityID", bytes32(entityID)))
        );

        return bytes32(entityID);
    }

    // version of use that restricts crafting to building owner, author or allow list
    // these restrictions will not be reflected in the UI unless you make
    // similar changes in BasicFactory.js
    /*function use(Game ds, bytes24 buildingInstance, bytes24 actor, bytes memory ) public override {
        State state = GetState(ds);
        CheckIsFriendlyUnit(state, actor, buildingInstance);

        ds.getDispatcher().dispatch(abi.encodeCall(Actions.CRAFT, (buildingInstance)));
    }*/

    // version of use that restricts crafting to units carrying a certain item
    /*function use(Game ds, bytes24 buildingInstance, bytes24 actor, bytes memory ) public override {
        // require carrying an idCard
        // you can change idCardItemId to another item id
        CheckIsCarryingItem(state, actor, idCardItemId);

        ds.getDispatcher().dispatch(abi.encodeCall(Actions.CRAFT, (buildingInstance)));
    }*/

    function GetState(Game ds) internal returns (State) {
        return ds.getState();
    }

    function GetBuildingOwner(State state, bytes24 buildingInstance) internal view returns (bytes24) {
        return state.getOwner(buildingInstance);
    }

    function GetBuildingAuthor(State state, bytes24 buildingInstance) internal view returns (bytes24) {
        bytes24 buildingKind = state.getBuildingKind(buildingInstance);
        return state.getOwner(buildingKind);
    }

    function CheckIsFriendlyUnit(State state, bytes24 actor, bytes24 buildingInstance) internal view {
        require(
            UnitOwnsBuilding(state, actor, buildingInstance) || UnitAuthoredBuilding(state, actor, buildingInstance)
                || UnitOwnedByFriendlyPlayer(state, actor),
            "Unit does not have permission to use this building"
        );
    }

    function UnitOwnsBuilding(State state, bytes24 actor, bytes24 buildingInstance) internal view returns (bool) {
        return state.getOwner(actor) == GetBuildingOwner(state, buildingInstance);
    }

    function UnitAuthoredBuilding(State state, bytes24 actor, bytes24 buildingInstance) internal view returns (bool) {
        return state.getOwner(actor) == GetBuildingAuthor(state, buildingInstance);
    }

    address[] private friendlyPlayerAddresses = [0x402462EefC217bf2cf4E6814395E1b61EA4c43F7];

    function UnitOwnedByFriendlyPlayer(State state, bytes24 actor) internal view returns (bool) {
        address ownerAddress = state.getOwnerAddress(actor);
        for (uint256 i = 0; i < friendlyPlayerAddresses.length; i++) {
            if (friendlyPlayerAddresses[i] == ownerAddress) {
                return true;
            }
        }
        return false;
    }

    // use cli command 'ds get items' for all current possible ids.
    bytes24 idCardItemId = 0x6a7a67f0b29554460000000100000064000000640000004c;

    function CheckIsCarryingItem(State state, bytes24 actor, bytes24 item) internal view {
        require((UnitIsCarryingItem(state, actor, item)), "Unit must be carrying specified item");
    }

    function UnitIsCarryingItem(State state, bytes24 actor, bytes24 item) internal view returns (bool) {
        for (uint8 bagIndex = 0; bagIndex < 2; bagIndex++) {
            bytes24 bag = state.getEquipSlot(actor, bagIndex);
            if (bag != 0) {
                for (uint8 slot = 0; slot < 4; slot++) {
                    (bytes24 resource, uint64 balance) = state.getItemSlot(bag, slot);
                    if (resource == item && balance > 0) {
                        return true;
                    }
                }
            }
        }
        return false;
    }
}