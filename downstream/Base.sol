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

using Schema for State;

contract Base is BuildingKind, IBase {
    uint256 constant BATTLE_TIMEOUT_BLOCKS = 60 / BLOCK_TIME_SECS;

    function startBattle() external {} // TODO: remove this as starting battle is done by adding attackers
    function claimWin() external {}
    
    function addSoldiers(uint64 amount) external {}
    function removeSoldiers(uint64 amount) external {}

    address public owner;

    string constant DATA_BATTLE_START_BLOCK = "battleStartBlock";

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
        } else if ((bytes4)(payload) == this.addSoldiers.selector) {
            (uint64 amount) = abi.decode(payload[4:], (uint64));
            _addSoldiers(ds, buildingInstance, actor, amount);
        } else {
            revert("Invalid function selector");
        }
    }

    function _addSoldiers(Game ds, bytes24 buildingInstance, bytes24 actor, uint64 amount) internal {
        State state = ds.getState();
        
        bytes24 tile = state.getFixedLocation(buildingInstance);
        bytes24 zone = Node.Zone(getTileZone(tile));
        
        Team team = LibUtils.getUnitTeam(state, zone, actor);

        require(team != Team.NONE, "Base: Player is not in any team");
        
        uint64 soldierCount = uint64(uint256(state.getData(buildingInstance, LibUtils.getSoliderCountKey(team))));
        
        // Start attack this is the first lot of attackers
        if (soldierCount == 0) {
            _startBattle(ds, buildingInstance);
        }

        soldierCount += amount;
        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, LibUtils.getSoliderCountKey(team), bytes32(uint256(soldierCount))))
        );

        // record our 'random' seed for this block
        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, LibUtils.getRndSeedKey(block.number), blockhash(block.number - 1)))
        );
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
            ds, Node.Tile(coords[0], coords[1], coords[2], coords[3]), mobileUnitID, false
        );
    }

    function _startBattle(Game ds, bytes24 buildingInstance) internal {
        // State state = ds.getState();

        // bytes24 tile = state.getFixedLocation(buildingInstance);
        // (int16 z,,,) = LibUtils.getTileCoords(tile);

        // bytes24 zoneID = Node.Zone(z);

        // {
        //     IZone zoneImpl = IZone(state.getImplementation(zoneID));
        //     require(zoneImpl.getGameState(state, zoneID) == GAME_STATE.IN_PROGRESS, "Base: Cannot start battle when game has ended");
        // }

        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, DATA_BATTLE_START_BLOCK, bytes32(block.number)))
        );
    }

    function _claimWin(Game ds, bytes24 buildingInstance, bytes24 actor) internal {
        State state = ds.getState();

        bytes24 tile = state.getFixedLocation(buildingInstance);


        uint256 timeoutBlock = uint256(state.getData(buildingInstance, LibUtils.getTileMatchTimeoutBlockKey(tile)));
        require (timeoutBlock != 0, "Match has not started yet");
        require(timeoutBlock < block.number , "Match has not timed out, cannot claim win yet");
        
        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, LibUtils.getTileMatchTimeoutBlockKey(tile), bytes32(0)))
        );

        bytes24 zone = Node.Zone(getTileZone(tile));
        IZone zoneImpl = IZone(state.getImplementation(zone));
        zoneImpl.setAreaWinner(ds, tile, actor, true);
    }

    function getTileZone(bytes24 tile) internal pure returns (int16 z) {
        int16[4] memory keys = CompoundKeyDecoder.INT16_ARRAY(tile);
        return (keys[0]);
    }
}
