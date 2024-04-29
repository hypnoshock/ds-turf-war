// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {State} from "cog/IState.sol";
import {Schema, Node, CompoundKeyDecoder} from "@ds/schema/Schema.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {BuildingKind} from "@ds/ext/BuildingKind.sol";
import {IWorld} from "./IWorld.sol";
import {IJudgeBuilding} from "./IJudgeBuilding.sol";
import {LibString} from "./LibString.sol";
import {LibUtils} from "./LibUtils.sol";
import {ITurfWars} from "./ITurfWars.sol";
import {IZone} from "./IZone.sol";

using Schema for State;

contract Base is BuildingKind {
    bytes32 constant LEVEL_FOUR_PLAYER = 0x4361756c64726f6e2d3200000000000000000000000000000000000000000000;
    bytes32 constant LEVEL_KNIFE_FIGHT = 0x4b6e6966655f46696768745f3200000000000000000000000000000000000000;
    bytes32 constant LEVEL_ISLE = 0x5468652049736c65000000000000000000000000000000000000000000000000;

    bytes32 constant SELECTED_LEVEL = LEVEL_KNIFE_FIGHT;
                                        
    bytes32 constant HERO = 0x48616c6265726469657200000000000000000000000000000000000000000000;

    function startBattle() external {}
    function claimWin() external {}

    address public owner;
    IWorld public world;
    bytes32 public firstMatchInWindow;
    ITurfWars public turfWars;

    modifier onlyOwner() {
        require(msg.sender == owner, "BattleBoy: Only owner can call this function");
        _;
    }

    function use(Game ds, bytes24 buildingInstance, bytes24 actor, bytes calldata payload ) public override {
        if ((bytes4)(payload) == this.startBattle.selector) {
            _startBattle(ds, buildingInstance);
        } else if ((bytes4)(payload) == this.claimWin.selector) {
            _claimWin(ds, buildingInstance, actor);
        } else {
            revert("Invalid function selector");
        }
    }

    function init(
        address _owner,
        address _skyStrifeWorld,
        address _turfWars,
        bytes32 _firstMatchInWindow
    ) public {
        if (owner != address(0) && msg.sender != owner) {
            revert("BattleBoy: Only owner can reinitialize");
        }
        owner = _owner;
        world = IWorld(_skyStrifeWorld);
        turfWars = ITurfWars(_turfWars);
        firstMatchInWindow = _firstMatchInWindow;
    }

    // -- Hooks

    function construct(Game ds, bytes24 buildingInstanceID, bytes24 mobileUnitID, bytes memory payload) public override {
        State state = ds.getState();
        int16[4] memory coords = abi.decode(payload, (int16[4]));
        bytes24 zone = Node.Zone(coords[0]);
        IZone zoneImpl = IZone(state.getImplementation(zone));
        require (address(zoneImpl) != address(0), "Base::construct - No implementation for zone");
        zoneImpl.setAreaWinner(ds, Node.Tile(coords[0], coords[1], coords[2], coords[3]), state.getOwner(mobileUnitID));
    }

    // -- Sky Strife Battles

    function setFirstMatchInWindow(bytes32 _firstMatchInWindow) public onlyOwner {
        firstMatchInWindow = _firstMatchInWindow;
    }

    function setSkyStrifeWorld(address _world) public onlyOwner {
        world = IWorld(_world);
    }

    function setTurfWars(address _turfWars) public onlyOwner {
        turfWars = ITurfWars(_turfWars);
    }

    function _startBattle(Game ds, bytes24 buildingInstance) internal {
        State state = ds.getState();
        
        uint256 count = uint256(state.getData(buildingInstance, "count")) + 1;
        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, "count", bytes32(count)))
        );
        bytes24 tile = state.getFixedLocation(buildingInstance);
        (int16 z, int16 q, int16 r, int16 s) = LibUtils.getTileCoords(tile);
        string memory name = string(abi.encodePacked(
            "TW_", 
            LibString.toString(uint256(uint16(z))), ":",
            LibString.toCrunkString(uint256(uint16(q)), 2),
            LibString.toCrunkString(uint256(uint16(r)), 2),
            LibString.toCrunkString(uint256(uint16(s)), 2),
            LibString.toString(uint256(count))));

        bytes32 entityID = _getEntityID(buildingInstance);

        require(address(turfWars) != address(0), "BattleBoy: TurfWars not set");
        turfWars.startBattle(name, firstMatchInWindow, entityID, SELECTED_LEVEL);

        string memory tileMatchKey = LibUtils.getTileMatchKey(tile);
        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, tileMatchKey, entityID))
        );
    }

    function _claimWin(Game ds, bytes24 buildingInstance, bytes24 actor) internal {
        State state = ds.getState();
        
        bytes24 tile = state.getFixedLocation(buildingInstance);
        bytes24 zone = Node.Zone(getTileZone(tile));
        string memory tileMatchKey = LibUtils.getTileMatchKey(tile);
        bytes32 entityID = state.getData(buildingInstance, tileMatchKey);
        
        require(entityID != 0, "No match to claim win for");

        bytes24 player = state.getOwner(actor);
        address playerAddress = state.getOwnerAddress(player);

        require(turfWars.isAddressWinner(playerAddress, entityID), "Player is not the winner");

        IZone zoneImpl = IZone(state.getImplementation(zone));
        zoneImpl.setAreaWinner(ds, tile, player);
    }

    function _getEntityID(bytes24 buildingInstance) view internal returns (bytes32) {
        return bytes32((uint256(keccak256(abi.encodePacked(buildingInstance, block.timestamp))) & 0xFFFFFFFF) << 224);
    }

    function getTileZone(bytes24 tile) internal pure returns (int16 z) {
        int16[4] memory keys = CompoundKeyDecoder.INT16_ARRAY(tile);
        return (keys[0]);
    }
}