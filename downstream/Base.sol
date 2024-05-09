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
import {IZone, GAME_STATE, DATA_SELECTED_LEVEL, TEAM_A, TEAM_B} from "./IZone.sol";
import {IBase} from "./IBase.sol";

using Schema for State;

contract Base is BuildingKind, IBase {
    bytes32 constant LEVEL_FOUR_PLAYER = 0x4361756c64726f6e2d3200000000000000000000000000000000000000000000;
    bytes32 constant LEVEL_KNIFE_FIGHT = 0x4b6e6966655f46696768745f3200000000000000000000000000000000000000;
    bytes32 constant LEVEL_ISLE = 0x49736c6500000000000000000000000000000000000000000000000000000000;
    bytes32 constant DEFAULT_LEVEL = LEVEL_ISLE;
    bytes32 constant HERO = 0x48616c6265726469657200000000000000000000000000000000000000000000;

    uint256 constant BATTLE_TIMEOUT_BLOCKS = 60 / BLOCK_TIME_SECS;

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
            ds, Node.Tile(coords[0], coords[1], coords[2], coords[3]), mobileUnitID, false
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
        (int16 z,,,) = LibUtils.getTileCoords(tile);

        bytes24 zoneID = Node.Zone(z);

        {
            IZone zoneImpl = IZone(state.getImplementation(zoneID));
            require(zoneImpl.getGameState(state, zoneID) == GAME_STATE.IN_PROGRESS, "Base: Cannot start battle when game has ended");
        }

        bytes32 matchID = _getMatchID(buildingInstance);
        string memory name = string(
            abi.encodePacked(
                "TW_",
                LibString.toString(uint256(uint16(z))),
                ":",
                LibString.toCrunkString(uint256(matchID) >> 224, 4)
            )
        );
        bytes32 level = state.getData(zoneID, DATA_SELECTED_LEVEL);
        if (level == bytes32(0)) {
            level = DEFAULT_LEVEL;
        }

        require(address(turfWars) != address(0), "Base: TurfWars not set");

        // turfWars.startBattle(name, firstMatchInWindow, matchID, level);
        turfWars.startPrivateBattle(name, firstMatchInWindow, matchID, level, getParticipantAddresses(state, zoneID));

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

        // if at least one person has joined the match then check for winner
        if (turfWars.hasAnyPlayerJoinedMatch(matchID)) {
            // Does this still eval true after a match has been won?
            require(turfWars.isAddressWinner(playerAddress, matchID), "Player is not the winner");
        } else {
            // require the match has timed out
            require(uint256(state.getData(buildingInstance, LibUtils.getTileMatchTimeoutBlockKey(tile))) < block.number , "Match has not timed out, cannot claim win yet");
        }

        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (buildingInstance, tileMatchKey, bytes32(0)))
        );

        IZone zoneImpl = IZone(state.getImplementation(zone));
        zoneImpl.setAreaWinner(ds, tile, actor, true);
        // zoneImpl.spawnHammer(ds, state, tile, 1);
    }

    function _getMatchID(bytes24 buildingInstance) internal view returns (bytes32) {
        return bytes32((uint256(keccak256(abi.encodePacked(buildingInstance, block.timestamp))) & 0xFFFFFFFF) << 224);
    }

    function getTileZone(bytes24 tile) internal pure returns (int16 z) {
        int16[4] memory keys = CompoundKeyDecoder.INT16_ARRAY(tile);
        return (keys[0]);
    }

    function getParticipantAddresses(State state, bytes24 zoneID)
        internal
        view
        returns (address[] memory addresses)
    {
        uint64 teamLengthA = uint64(uint256(state.getData(zoneID, string(abi.encodePacked(TEAM_A, "Length")))));
        uint64 teamLengthB = uint64(uint256(state.getData(zoneID, string(abi.encodePacked(TEAM_B, "Length")))));
        addresses = new address[](teamLengthA + teamLengthB + 3);

        addresses[0] = owner; // Owner can always join
        addresses[1] = address(0x47e279710dD887F90A4799F6503D8E8BaBb907FC); // dev accounts
        addresses[2] = address(0x2dC54359C1755e67D9149291860c311F3ba7cE18); // dev accounts
        
        // Team A
        uint64 offset = 3;
        for (uint64 i = 0; i < teamLengthA; i++) {
            string memory teamUnitKey = string(abi.encodePacked(TEAM_A, "Unit_", LibString.toString(i)));
            bytes24 unitId = bytes24(state.getData(zoneID, teamUnitKey));
            addresses[i + offset] = state.getOwnerAddress(state.getOwner(unitId));
        }

        // Team B
        offset += teamLengthA;
        for (uint64 i = 0; i < teamLengthB; i++) {
            string memory teamUnitKey = string(abi.encodePacked(TEAM_B, "Unit_", LibString.toString(i)));
            bytes24 unitId = bytes24(state.getData(zoneID, teamUnitKey));
            addresses[i + offset] = state.getOwnerAddress(state.getOwner(unitId));
        }
    }
}
