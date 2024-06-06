// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {Dispatcher} from "cog/IDispatcher.sol";
import {State, CompoundKeyDecoder} from "cog/IState.sol";
import {Schema, CombatWinState, Node, Q, R, S, BLOCK_TIME_SECS} from "@ds/schema/Schema.sol";
import {ZoneKind} from "@ds/ext/ZoneKind.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {LibUtils} from "./LibUtils.sol";
import {LibTeamState, TeamState} from "./LibTeamState.sol";
import {IZone, GAME_STATE, HAMMER_ITEM, PRIZE_ITEM, Team, TEAM_A, TEAM_B, DATA_HAS_CLAIMED_PRIZES} from "./IZone.sol";
import "@ds/utils/LibString.sol";

using Schema for State;

contract TurfWarsZone is ZoneKind, IZone {
    function join(bytes24 hqTileID) external {}
    function setReady() external {}
    function unsetReady() external {}
    function reset(bytes24[] memory dirtyTiles, bytes24[] memory baseBuildings) external {}
    function destroyTileBag(bytes24 tileID, bytes24 bagID, bytes24[] memory slotContents) external {}
    // function claim() external {}

    int16 constant DEFAULT_CLAIM_RANGE = 2;
    uint64 constant DEFAULT_GAME_DURATION_BLOCKS = 120 * 60 / BLOCK_TIME_SECS; // (15 * 60)
    uint64 constant DEFAULT_HAMMER_COUNT = 10;

    // Data keys
    string constant DATA_GAME_STATE = "gameState";
    string constant DATA_READY = "ready";
    string constant DATA_CLAIM_RANGE = "claimRange";
    string constant DATA_GAME_DURATION_BLOCKS = "gameDurationBlocks";
    string constant DATA_START_BLOCK = "startBlock";
    string constant DATA_END_BLOCK = "endBlock";

    function use(Game ds, bytes24 zoneID, bytes24 mobileUnitID, bytes calldata payload) public override {
        State state = ds.getState();
        if ((bytes4)(payload) == this.join.selector) {
            bytes24 hqTileID = abi.decode(payload[4:], (bytes24));
            _join(ds, state, mobileUnitID, zoneID, hqTileID);
        } else if ((bytes4)(payload) == this.setReady.selector) {
            _setReady(ds, state, mobileUnitID, zoneID);
        } else if ((bytes4)(payload) == this.unsetReady.selector) {
            _unsetReady(ds, state, mobileUnitID, zoneID);
        } else if ((bytes4)(payload) == this.reset.selector) {
            (bytes24[] memory dirtyTiles, bytes24[] memory baseBuildings) =
                abi.decode(payload[4:], (bytes24[], bytes24[]));
            _reset(ds, state, zoneID, dirtyTiles, baseBuildings);
        } else if ((bytes4)(payload) == this.destroyTileBag.selector) {
            (bytes24 tileID, bytes24 bagID, bytes24[] memory slotContents) =
                abi.decode(payload[4:], (bytes24, bytes24, bytes24[]));
            ds.getDispatcher().dispatch(
                abi.encodeCall(Actions.DEV_DESTROY_BAG, (bagID, address(0), tileID, uint8(0), slotContents))
            );
        } else {
            revert("TurfWarsZone: Invalid function signature");
        }
    }

    // TODO: only bases can call this
    function setAreaWinner(Game ds, bytes24 origin, bytes24 mobileUnit, bool destroyBuilding) public {
        (int16 originZ, int16 originQ, int16 originR, int16 originS) = getTileCoords(origin);
        bytes24 zoneID = Node.Zone(originZ);

        State state = ds.getState();
        if (getGameState(state, zoneID) != GAME_STATE.IN_PROGRESS) {
            return;
        }

        // Probably mega expensive. Callilng _setTileWinner each time probably is
        {
            int16 range = int16(int256(uint256(state.getData(zoneID, DATA_CLAIM_RANGE))));
            if (range == 0) {
                range = DEFAULT_CLAIM_RANGE;
            }

            for (int16 q = originQ - range; q <= originQ + range; q++) {
                for (int16 r = originR - range; r <= originR + range; r++) {
                    int16 s = -q - r;
                    bytes24 nextTile = Node.Tile(originZ, q, r, s);
                    if (distance(origin, nextTile) <= uint256(uint16(range))) {
                        if (destroyBuilding || !_hasTileBeenWon(ds, nextTile, zoneID)) {
                            _setTileWinner(ds, nextTile, mobileUnit, zoneID);
                        }
                        // tileCount++;
                    }
                }
            }
        }

        if (destroyBuilding) {
            _spawnHammer(ds, origin, 1);
            ds.getDispatcher().dispatch(
                abi.encodeCall(Actions.DEV_DESTROY_BUILDING, (originZ, originQ, originR, originS))
            );
        }
    }

    function distance(bytes24 tileA, bytes24 tileB) internal pure returns (uint256) {
        int16[4] memory a = CompoundKeyDecoder.INT16_ARRAY(tileA);
        int16[4] memory b = CompoundKeyDecoder.INT16_ARRAY(tileB);
        return uint256(
            (abs(int256(a[Q]) - int256(b[Q])) + abs(int256(a[R]) - int256(b[R])) + abs(int256(a[S]) - int256(b[S]))) / 2
        );
    }

    function abs(int256 n) internal pure returns (int256) {
        return n >= 0 ? n : -n;
    }

    function _setReady(Game ds, State state, bytes24 mobileUnitID, bytes24 zoneID) private {
        // Check if game is already in progress
        if (getGameState(state, zoneID) != GAME_STATE.NOT_STARTED) {
            revert("Game already in progress");
        }

        // TODO: Check if caller is the owner of the unit
        // if (state.getOwner(mobileUnitID) != Node.Player(msg.sender)) {
        //     revert("Not owner of unit");
        // }

        // Get unit team
        Team team = LibUtils.getUnitTeam(state, zoneID, mobileUnitID);
        if (team == Team.NONE) {
            revert("Unit not in team");
        }

        // Check if other team is ready
        if (Team(uint256(state.getData(zoneID, DATA_READY))) == (team == Team.A ? Team.B : Team.A)) {
            // Other team ready, start game
            _startGame(ds, state, zoneID);
        } else {
            // Set team as ready
            _setDataOnZone(ds.getDispatcher(), zoneID, DATA_READY, bytes32(uint256(team)));
        }
    }

    function _startGame(Game ds, State state, bytes24 zoneID) internal {
        // Set game state to in progress
        _setDataOnZone(ds.getDispatcher(), zoneID, DATA_GAME_STATE, bytes32(uint256(GAME_STATE.IN_PROGRESS)));

        // Set start block
        _setDataOnZone(ds.getDispatcher(), zoneID, DATA_START_BLOCK, bytes32(uint256(block.number)));

        // Set end block
        uint256 gameDurationBlocks = uint256(state.getData(zoneID, DATA_GAME_DURATION_BLOCKS));
        if (gameDurationBlocks == 0) {
            gameDurationBlocks = DEFAULT_GAME_DURATION_BLOCKS;
        }
        _setDataOnZone(ds.getDispatcher(), zoneID, DATA_END_BLOCK, bytes32(uint256(block.number) + gameDurationBlocks));
    }

    function _unsetReady(Game ds, State state, bytes24 mobileUnitID, bytes24 zoneID) private {
        // Check if game is already in progress
        if (getGameState(state, zoneID) != GAME_STATE.NOT_STARTED) {
            revert("Game already in progress");
        }

        // TODO: Check if caller is the owner of the unit
        // if (state.getOwner(mobileUnitID) != Node.Player(msg.sender)) {
        //     revert("Not owner of unit");
        // }

        // Get unit team
        Team team = LibUtils.getUnitTeam(state, zoneID, mobileUnitID);
        if (team == Team.NONE) {
            revert("Unit not in team");
        }

        // Check that the team was set to ready
        require(Team(uint256(state.getData(zoneID, DATA_READY))) == team, "Team not ready");

        _setDataOnZone(ds.getDispatcher(), zoneID, DATA_READY, bytes32(uint256(Team.NONE)));
    }

    function _join(Game ds, State state, bytes24 unitID, bytes24 zoneID, bytes24 hqTileID) private {
        // check game not in progress
        if (getGameState(state, zoneID) != GAME_STATE.NOT_STARTED) {
            revert("Cannot join game in progress");
        }

        // Check if unit has already joined
        if (
            LibUtils.isUnitInTeam(state, zoneID, TEAM_A, unitID) || LibUtils.isUnitInTeam(state, zoneID, TEAM_B, unitID)
        ) {
            revert("Already joined");
        }

        uint64 teamALength = uint64(uint256(state.getData(zoneID, string(abi.encodePacked(TEAM_A, "Length")))));
        uint64 teamBLength = uint64(uint256(state.getData(zoneID, string(abi.encodePacked(TEAM_B, "Length")))));

        // assign a team
        _assignUnitToTeam(
            ds,
            (teamALength <= teamBLength) ? TEAM_A : TEAM_B,
            (teamALength <= teamBLength) ? teamALength : teamBLength,
            unitID,
            zoneID
        );

        _spawnHammer(ds, hqTileID, DEFAULT_HAMMER_COUNT);
    }

    function _spawnHammer(Game ds, bytes24 tileID, uint64 count) private {
        _spawnItem(ds.getDispatcher(), tileID, HAMMER_ITEM, count);
    }

    // TODO: restrict to TurfWarsHQ
    function spawnPrizes(Game ds, bytes24 tileID, uint64 count) public {
        // address hqImpl = ds.getState().getImplementation(TURFWARS_HQ);
        // require(msg.sender == hqImpl, "Only TurfWarsHQ can call this");

        _spawnItem(ds.getDispatcher(), tileID, PRIZE_ITEM, count);
    }

    // TODO: restrict to TurfWarsHQ
    function setHasClaimedPrizes(Game ds, bytes24 zoneID) external {
        // address hqImpl = ds.getState().getImplementation(TURFWARS_HQ);
        // require(msg.sender == hqImpl, "Only TurfWarsHQ can call this");

        _setDataOnZone(ds.getDispatcher(), zoneID, DATA_HAS_CLAIMED_PRIZES, bytes32(uint256(1)));
    }

    function _spawnItem(Dispatcher dispatcher, bytes24 tileID, bytes24 item, uint64 count) private {
        (int16 z, int16 q, int16 r, int16 s) = getTileCoords(tileID);

        bytes24[] memory items = new bytes24[](4);
        uint64[] memory balances = new uint64[](4);
        items[0] = item;
        items[1] = bytes24(0);
        items[2] = bytes24(0);
        items[3] = bytes24(0);
        balances[0] = count;
        balances[1] = 0;
        balances[2] = 0;
        balances[3] = 0;

        dispatcher.dispatch(
            abi.encodeCall(
                Actions.DEV_SPAWN_BAG,
                (
                    z,
                    q,
                    r,
                    s,
                    uint8(0), // equip slot
                    items,
                    balances
                )
            )
        );
    }

    function _assignUnitToTeam(Game ds, string memory team, uint64 teamLength, bytes24 unitID, bytes24 zoneID)
        internal
    {
        Dispatcher dispatcher = ds.getDispatcher();
        // TODO: use enums instead of strings and get rid of keccak
        if (keccak256(abi.encodePacked(team)) == keccak256(abi.encodePacked(TEAM_A))) {
            _processTeam(dispatcher, zoneID, TEAM_A, teamLength, unitID);
        } else if (keccak256(abi.encodePacked(team)) == keccak256(abi.encodePacked(TEAM_B))) {
            _processTeam(dispatcher, zoneID, TEAM_B, teamLength, unitID);
        }
    }

    function _processTeam(
        Dispatcher dispatcher,
        bytes24 zoneID,
        string memory teamPrefix,
        uint64 teamLength,
        bytes24 unitID
    ) private {
        // adding to teamXUnit_X
        string memory teamUnitIndex =
            string(abi.encodePacked(teamPrefix, "Unit_", LibString.toString(uint256(teamLength))));
        _setDataOnZone(dispatcher, zoneID, teamUnitIndex, bytes32(unitID));
        _setDataOnZone(
            dispatcher, zoneID, string(abi.encodePacked(teamPrefix, "Length")), bytes32(uint256(teamLength) + 1)
        );
    }

    function getTileCoords(bytes24 tile) internal pure returns (int16 z, int16 q, int16 r, int16 s) {
        int16[4] memory keys = CompoundKeyDecoder.INT16_ARRAY(tile);
        return (keys[0], keys[1], keys[2], keys[3]);
    }

    // TODO: Only a player or owner can call this
    function _reset(Game ds, State state, bytes24 zoneID, bytes24[] memory dirtyTiles, bytes24[] memory baseBuildings)
        internal
    {
        Dispatcher dispatcher = ds.getDispatcher();

        // TODO: If game is finished, check that claims have been made before allowing reset
        // if (getGameState(state, zoneID) == GAME_STATE.FINISHED) {
        //     require(state.getData(zoneID, DATA_HAS_CLAIMED_PRIZES) == bytes32(uint256(1)));
        // }

        // Reset winner on each tile
        uint256 teamAScore = 0;
        uint256 teamBScore = 0;
        for (uint256 i = 0; i < dirtyTiles.length; i++) {
            bytes24 tile = dirtyTiles[i];
            (int16 tileZoneKey,,,) = getTileCoords(tile);
            bytes24 tileZone = Node.Zone(tileZoneKey);
            require(tileZone == zoneID, "Tile not in zone");
            bytes24 winningUnit = bytes24(ds.getState().getData(zoneID, LibUtils.getTileWinnerKey(tile)));
            if (winningUnit != bytes24(0)) {
                if (LibUtils.isUnitInTeam(state, zoneID, TEAM_A, winningUnit)) {
                    teamAScore++;
                } else {
                    teamBScore++;
                }

                _setTileWinner(ds, tile, bytes24(0), tileZone);
            }
        }

        // Destroy all base buildings
        for (uint256 i = 0; i < baseBuildings.length; i++) {
            bytes24 buildingTile = state.getFixedLocation(baseBuildings[i]);
            (int16 z, int16 q, int16 r, int16 s) = getTileCoords(buildingTile);
            require(Node.Zone(z) == zoneID, "Base building not in zone");
            dispatcher.dispatch(abi.encodeCall(Actions.DEV_DESTROY_BUILDING, (z, q, r, s)));

            // TODO: Contract too large
            // ds.getDispatcher().dispatch(
            //     abi.encodeCall(Actions.SET_DATA_ON_BUILDING, (baseBuildings[i], "initState", bytes32(0)))
            // );
        }

        _setDataOnZone(dispatcher, zoneID, DATA_GAME_STATE, bytes32(uint256(GAME_STATE.NOT_STARTED)));
        _setDataOnZone(dispatcher, zoneID, string(abi.encodePacked(TEAM_A, "Length")), bytes32(0));
        _setDataOnZone(dispatcher, zoneID, string(abi.encodePacked(TEAM_B, "Length")), bytes32(0));
        _setDataOnZone(dispatcher, zoneID, DATA_READY, bytes32(uint256(Team.NONE)));
        _setDataOnZone(dispatcher, zoneID, DATA_END_BLOCK, bytes32(uint256(block.number)));
        _setDataOnZone(dispatcher, zoneID, DATA_HAS_CLAIMED_PRIZES, bytes32(0));
        _setDataOnZone(dispatcher, zoneID, LibUtils.getTeamStateKey(Team.A), bytes32(0));
        _setDataOnZone(dispatcher, zoneID, LibUtils.getTeamStateKey(Team.B), bytes32(0));
    }

    function burnTileBag(Game ds, bytes24 tile, bytes24 bagID, uint8 equipSlot) public {
        // NOTE: The empty 'slotContents' array is due to the DEV_DESTROY_BAG action using the length of the array to determine the number of slots to destroy. MAD!!
        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.DEV_DESTROY_BAG, (bagID, address(0), tile, equipSlot, new bytes24[](4)))
        );
    }

    // -- Hooks

    function onUnitArrive(Game ds, bytes24 zoneID, bytes24 mobileUnitID) external override {
        State state = ds.getState();
        bytes24 mobileUnitTile = state.getCurrentLocation(mobileUnitID, uint64(block.number));
        // (int16 z,,,) = getTileCoords(mobileUnitTile);

        GAME_STATE gameState = getGameState(state, zoneID);

        if (gameState == GAME_STATE.NOT_STARTED) {
            // NOTE: Contract at size limit. Removing movement restrictions for now

            // -- Unit move locking
            // bytes24 centerTile = Node.Tile(z, 0, 0, 0);
            // if (mobileUnitTile == centerTile) {
            //     return;
            // }

            // bool isTeamA = LibUtils.isUnitInTeam(state, zoneID, TEAM_A, mobileUnitID);
            // bool isTeamB = LibUtils.isUnitInTeam(state, zoneID, TEAM_B, mobileUnitID);

            // // Units who are on a team are allowed to move to the starting positions
            // // TODO: Make these positions configurable / dynamic
            // if (isTeamA && mobileUnitTile == Node.Tile(z, 0, -5, 5)) {
            //     return;
            // } else if (isTeamB && mobileUnitTile == Node.Tile(z, 0, 5, -5)) {
            //     return;
            // }

            // // Units that aren't in a team but where already in the zone before the game started can move (to allow them to walk back to centre)
            // // If they are on the centre tile they are locked to it
            // if (!isTeamA && !isTeamB) {
            //     bytes24 mobileUnitPrevTile = state.getPrevLocation(mobileUnitID);
            //     (int16 prevZ,,,) = getTileCoords(mobileUnitTile);
            //     if (prevZ == z && mobileUnitPrevTile != centerTile) {
            //         return;
            //     }
            // }

            // revert("Unit cannot move, Game not started");
        } else if (gameState == GAME_STATE.IN_PROGRESS) {
            bool isUnitInTeam = LibUtils.isUnitInTeam(state, zoneID, TEAM_A, mobileUnitID)
                || LibUtils.isUnitInTeam(state, zoneID, TEAM_B, mobileUnitID);
            require(isUnitInTeam, "Cannot move, unit not on a team");

            // Claim unclaimed tile
            if (!_hasTileBeenWon(ds, mobileUnitTile, zoneID)) {
                _setTileWinner(ds, mobileUnitTile, mobileUnitID, zoneID);
            }
        } else if (gameState == GAME_STATE.FINISHED) {
            // NOTE: Contract at size limit. Removing movement restrictions for now

            // bytes24 centerTile = Node.Tile(z, 0, 0, 0);
            // if (mobileUnitTile == centerTile) {
            //     return;
            // }

            // // Units already in zone are allowed to walk back to the centre
            // bytes24 mobileUnitPrevTile = state.getPrevLocation(mobileUnitID);
            // (int16 prevZ,,,) = getTileCoords(mobileUnitPrevTile);
            // if (prevZ == z && mobileUnitPrevTile != centerTile) {
            //     return;
            // }

            // revert("Unit cannot move, game must be reset first");
        }
    }

    // NOTE: Contract close to size limit. This can get dropped if we need more space
    function onCombatStart(Game, /*ds*/ bytes24, /*zoneID*/ bytes24, /*mobileUnitID*/ bytes24 /*sessionID*/ )
        external
        pure
        override
    {
        revert("Combat not supported in this zone");
    }

    // NOTE: Contract close to size limit. This can get dropped if we need more space. Below is ~500bytes
    bytes24 constant BASE_BUILDING = 0xbe92755c0000000000000000a9c1e4010000000000000004;

    function onContructBuilding(Game ds, bytes24 zoneID, bytes24 mobileUnitID, bytes24 buildingInstance)
        external
        override
    {
        State state = ds.getState();
        require(getGameState(state, zoneID) == GAME_STATE.IN_PROGRESS, "Cannot build until game starts");
        bytes24 buildingKind = state.getBuildingKind(buildingInstance);

        // require(buildingKind == BASE_BUILDING, "Only base buildings can be constructed in this zone");

        if (buildingKind == BASE_BUILDING) {
            // Team can only directly build one base
            Team team = LibUtils.getUnitTeam(state, zoneID, mobileUnitID);
            TeamState memory teamState =
                LibTeamState.decodeTeamState(uint256(state.getData(zoneID, LibUtils.getTeamStateKey(team))));

            require(!teamState.hasPlacedInitHQ, "Team has already placed a base");

            teamState.hasPlacedInitHQ = true;

            _setDataOnZone(
                ds.getDispatcher(),
                zoneID,
                LibUtils.getTeamStateKey(team),
                bytes32(LibTeamState.encodeTeamState(teamState))
            );
        }
    }

    // -- Helpers

    function getGameState(State state, bytes24 zoneID) public view returns (GAME_STATE) {
        GAME_STATE gameState = GAME_STATE(uint256(state.getData(zoneID, DATA_GAME_STATE)));
        if (gameState == GAME_STATE.IN_PROGRESS && block.number >= uint256(state.getData(zoneID, DATA_END_BLOCK))) {
            return GAME_STATE.FINISHED;
        }
        return gameState;
    }

    function _hasTileBeenWon(Game ds, bytes24 tile, bytes24 zoneID) internal returns (bool) {
        return ds.getState().getData(zoneID, LibUtils.getTileWinnerKey(tile)) != bytes32(0);
    }

    function _setTileWinner(Game ds, bytes24 tile, bytes24 mobileUnit, bytes24 zoneID) internal {
        ds.getDispatcher().dispatch(
            abi.encodeCall(Actions.SET_DATA_ON_ZONE, (zoneID, LibUtils.getTileWinnerKey(tile), mobileUnit))
        );
    }

    function _setDataOnZone(Dispatcher dispatcher, bytes24 zoneID, string memory key, bytes32 value) internal {
        dispatcher.dispatch(abi.encodeCall(Actions.SET_DATA_ON_ZONE, (zoneID, key, value)));
    }
}
