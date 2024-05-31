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
    uint256 constant BATTLE_TIMEOUT_BLOCKS = 300; //60 / BLOCK_TIME_SECS;

    function claimWin() external {}

    function addSoldiers(uint8 amount) external {}
    function removeSoldiers(uint64 amount) external {}

    address public owner;

    string constant DATA_BATTLE_START_BLOCK = "battleStartBlock";

    struct TeamState {
        uint8 team;
        uint8 soldierCount;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Base: Only owner can call this function");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function use(Game ds, bytes24 buildingInstance, bytes24 actor, bytes calldata payload) public override {
        if ((bytes4)(payload) == this.claimWin.selector) {
            _claimWin(ds, buildingInstance, actor);
        } else if ((bytes4)(payload) == this.addSoldiers.selector) {
            (uint8 amount) = abi.decode(payload[4:], (uint8));
            _addSoldiers(ds, buildingInstance, actor, amount);
        } else {
            revert("Invalid function selector");
        }
    }

    function _addSoldiers(Game ds, bytes24 buildingInstance, bytes24 actor, uint8 amount) internal {
        State state = ds.getState();

        bytes24 tile = state.getFixedLocation(buildingInstance);
        bytes24 zone = Node.Zone(getTileZone(tile));

        Team team = LibUtils.getUnitTeam(state, zone, actor);

        require(team != Team.NONE, "Base: Player is not in any team");

        if (state.getData(buildingInstance, DATA_BATTLE_START_BLOCK) == bytes32(0)) {
            _startBattle(ds, buildingInstance);
        }

        ds.getDispatcher().dispatch(
            abi.encodeCall(
                Actions.SET_DATA_ON_BUILDING,
                (buildingInstance, LibUtils.getStateChangeKey(block.number), _encodeStateUpdate(team, amount))
            )
        );

        // record our 'random' seed for this block
        ds.getDispatcher().dispatch(
            abi.encodeCall(
                Actions.SET_DATA_ON_BUILDING,
                (buildingInstance, LibUtils.getRndSeedKey(block.number), blockhash(block.number - 1))
            )
        );
    }

    function _encodeStateUpdate(Team team, uint8 soldierAmount) internal pure returns (bytes32) {
        return bytes32(uint256(team) | (uint256(soldierAmount) << 8));
    }

    function _decodeStateUpdate(bytes32 stateUpdate) internal pure returns (Team team, uint8 soldierAmount) {
        return (Team(uint8(uint256(stateUpdate))), uint8(uint256(stateUpdate) >> 8));
    }

    function getBattleState(Game ds, bytes24 buildingInstance, uint256 blockNumber)
        public
        returns (TeamState[] memory teamStates, bool isFinished)
    {
        State state = ds.getState();

        teamStates = new TeamState[](2);

        uint256 startBlock = uint256(state.getData(buildingInstance, DATA_BATTLE_START_BLOCK));
        if (startBlock == 0) {
            return (teamStates, false);
        }

        uint256 totalBlocks = blockNumber - startBlock;
        if (totalBlocks > BATTLE_TIMEOUT_BLOCKS) {
            totalBlocks = BATTLE_TIMEOUT_BLOCKS;

            // battle has timed out so ends even if both sides still have soldiers
            isFinished = true;
        }

        // TODO: Find the team that is on defence so we know who attacks first

        bytes32 rndSeed;
        for (uint256 i = 0; i < totalBlocks; i++) {
            bytes32 stateUpdate = state.getData(buildingInstance, LibUtils.getStateChangeKey(startBlock + i));
            if (stateUpdate != bytes32(0)) {
                (Team team, uint8 soldierAmount) = _decodeStateUpdate(stateUpdate);
                teamStates[uint8(team) - 1].soldierCount += soldierAmount;
                rndSeed = state.getData(buildingInstance, LibUtils.getRndSeedKey(startBlock + i));
            }

            if (teamStates[uint8(Team.A) - 1].soldierCount == 0 || teamStates[uint8(Team.B) - 1].soldierCount == 0) {
                return (teamStates, true);
            }

            // Attackers attack first
            for (uint8 j = 0; j < teamStates[uint8(Team.A) - 1].soldierCount; j++) {
                teamStates[uint8(Team.B) - 1].soldierCount--;
                if (teamStates[uint8(Team.B) - 1].soldierCount == 0) {
                    return (teamStates, true);
                }
            }

            // Defenders attack second
            for (uint8 j = 0; j < teamStates[uint8(Team.B) - 1].soldierCount; j++) {
                teamStates[uint8(Team.A) - 1].soldierCount--;
                if (teamStates[uint8(Team.A) - 1].soldierCount == 0) {
                    return (teamStates, true);
                }
            }
        }

        return (teamStates, isFinished);
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
        zoneImpl.setAreaWinner(ds, Node.Tile(coords[0], coords[1], coords[2], coords[3]), mobileUnitID, false);
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
            abi.encodeCall(
                Actions.SET_DATA_ON_BUILDING, (buildingInstance, DATA_BATTLE_START_BLOCK, bytes32(block.number))
            )
        );
    }

    function _claimWin(Game ds, bytes24 buildingInstance, bytes24 actor) internal {
        State state = ds.getState();

        bytes24 tile = state.getFixedLocation(buildingInstance);

        uint256 timeoutBlock = uint256(state.getData(buildingInstance, LibUtils.getTileMatchTimeoutBlockKey(tile)));
        require(timeoutBlock != 0, "Match has not started yet");
        require(timeoutBlock < block.number, "Match has not timed out, cannot claim win yet");

        ds.getDispatcher().dispatch(
            abi.encodeCall(
                Actions.SET_DATA_ON_BUILDING, (buildingInstance, LibUtils.getTileMatchTimeoutBlockKey(tile), bytes32(0))
            )
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
