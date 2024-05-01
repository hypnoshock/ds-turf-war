// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {State} from "cog/IState.sol";
import {Schema, Node, CompoundKeyDecoder, BLOCK_TIME_SECS} from "@ds/schema/Schema.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {BuildingKind} from "@ds/ext/BuildingKind.sol";
import {IWorld} from "./IWorld.sol";
import {LibString} from "./LibString.sol";
import {LibUtils} from "./LibUtils.sol";
import {ITurfWars} from "./ITurfWars.sol";
import {IZone, GAME_STATE} from "./IZone.sol";
import {IBase} from "./IBase.sol";

using Schema for State;

contract Base is BuildingKind, IBase {
    bytes32 constant LEVEL_FOUR_PLAYER = 0x4361756c64726f6e2d3200000000000000000000000000000000000000000000;
    bytes32 constant LEVEL_KNIFE_FIGHT = 0x4b6e6966655f46696768745f3200000000000000000000000000000000000000;
    bytes32 constant LEVEL_ISLE = 0x5468652049736c65000000000000000000000000000000000000000000000000;
    bytes32 constant SELECTED_LEVEL = LEVEL_KNIFE_FIGHT;
    bytes32 constant HERO = 0x48616c6265726469657200000000000000000000000000000000000000000000;

    uint256 constant BATTLE_TIMEOUT_BLOCKS = 20 / BLOCK_TIME_SECS;

    function startBattle() external {}
    function claimWin() external {}

    address public owner;
    IWorld public world;
    bytes32 public firstMatchInWindow;
    ITurfWars public turfWars;

    modifier onlyOwner() {
        require(msg.sender == owner, "Base: Only owner can call this function");
        _;
    }

    function use(Game ds, bytes24 buildingInstance, bytes24 actor, bytes calldata payload) public override {
        if ((bytes4)(payload) == this.startBattle.selector) {
            _startBattle(ds, buildingInstance);
        } else if ((bytes4)(payload) == this.claimWin.selector) {
            _claimWin(ds, buildingInstance, actor);
        } else {
            revert("Invalid function selector");
        }
    }

    function init(address _owner, address _skyStrifeWorld, address _turfWars, bytes32 _firstMatchInWindow) public {
        if (owner != address(0) && msg.sender != owner) {
            revert("Base: Only owner can reinitialize");
        }
        owner = _owner;
        world = IWorld(_skyStrifeWorld);
        turfWars = ITurfWars(_turfWars);
        firstMatchInWindow = _firstMatchInWindow;
    }

    // -- Hooks

    function construct(Game ds, bytes24, /*buildingInstanceID*/ bytes24 mobileUnitID, bytes memory payload)
        public
        override
    {
        State state = ds.getState();
        int16[4] memory coords = abi.decode(payload, (int16[4]));
        bytes24 zone = Node.Zone(coords[0]);
        IZone zoneImpl = IZone(state.getImplementation(zone));
        require(address(zoneImpl) != address(0), "Base::construct - No implementation for zone");
        zoneImpl.setAreaWinner(
            ds, Node.Tile(coords[0], coords[1], coords[2], coords[3]), state.getOwner(mobileUnitID), false
        );
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

        bytes24 tile = state.getFixedLocation(buildingInstance);
        (int16 z, int16 q, int16 r, int16 s) = LibUtils.getTileCoords(tile);

        bytes24 zoneID = Node.Zone(z);
        IZone zoneImpl = IZone(state.getImplementation(zoneID));

        require(zoneImpl.getGameState(state, zoneID) == GAME_STATE.IN_PROGRESS, "Base: Cannot start battle when game has ended");

        uint256 count = uint256(state.getData(buildingInstance, "count")) + 1;
        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, "count", bytes32(count)))
        );

        string memory name = string(
            abi.encodePacked(
                "TW_",
                LibString.toString(uint256(uint16(z))),
                ":",
                LibString.toCrunkString(uint256(uint16(q)), 2),
                LibString.toCrunkString(uint256(uint16(r)), 2),
                LibString.toCrunkString(uint256(uint16(s)), 2),
                LibString.toString(uint256(count))
            )
        );

        bytes32 matchID = _getMatchID(buildingInstance);

        require(address(turfWars) != address(0), "Base: TurfWars not set");
        turfWars.startBattle(name, firstMatchInWindow, matchID, SELECTED_LEVEL);

        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, LibUtils.getTileMatchKey(tile), matchID))
        );

        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, LibUtils.getTileMatchTimeoutBlockKey(tile), bytes32(block.number + BATTLE_TIMEOUT_BLOCKS )))
        );
    }

    function _claimWin(Game ds, bytes24 buildingInstance, bytes24 actor) internal {
        State state = ds.getState();

        bytes24 tile = state.getFixedLocation(buildingInstance);
        bytes24 zone = Node.Zone(getTileZone(tile));
        string memory tileMatchKey = LibUtils.getTileMatchKey(tile);
        bytes32 matchID = state.getData(buildingInstance, tileMatchKey);

        require(matchID != 0, "No match to claim win for");

        bytes24 player = state.getOwner(actor);
        address playerAddress = state.getOwnerAddress(player);

        // Enforce the claimer is the winner if the battle has ended
        // TODO: check if battle started rather than checking for winner
        if (uint256(state.getData(buildingInstance, LibUtils.getTileMatchTimeoutBlockKey(tile))) > block.number || turfWars.getWinningPlayer(matchID) != bytes32(0)) {
            require(turfWars.isAddressWinner(playerAddress, matchID), "Player is not the winner");
        }

        // TODO: Don't allow claiming if the tile already belongs to the claimer's team

        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, tileMatchKey, bytes32(0)))
        );

        IZone zoneImpl = IZone(state.getImplementation(zone));
        zoneImpl.setAreaWinner(ds, tile, player, true);
        // zoneImpl.spawnHammer(ds, state, tile, 1);
    }

    function _getMatchID(bytes24 buildingInstance) internal view returns (bytes32) {
        return bytes32((uint256(keccak256(abi.encodePacked(buildingInstance, block.timestamp))) & 0xFFFFFFFF) << 224);
    }

    function getTileZone(bytes24 tile) internal pure returns (int16 z) {
        int16[4] memory keys = CompoundKeyDecoder.INT16_ARRAY(tile);
        return (keys[0]);
    }
}
