// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/IGame.sol";
import {State} from "cog/IState.sol";
import {Schema, Node} from "@ds/schema/Schema.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {BuildingKind} from "@ds/ext/BuildingKind.sol";
import {LibUtils} from "./LibUtils.sol";
import {Team} from "./IZone.sol";
import {LibTeamState, TeamState} from "./LibTeamState.sol";

using Schema for State;

contract LongbowFactory is BuildingKind {
    function use(Game ds, bytes24 buildingInstance, bytes24 mobileUnitID, bytes memory /*payload*/ ) public override {
        State state = ds.getState();

        bytes24 mobileUnitTile = state.getCurrentLocation(mobileUnitID, uint64(block.number));
        (int16 z,,,) = LibUtils.getTileCoords(mobileUnitTile);
        bytes24 zoneID = Node.Zone(z);

        Team unitTeam = LibUtils.getUnitTeam(state, zoneID, mobileUnitID);
        Team tileTeam = LibUtils.getTileTeam(state, zoneID, state.getFixedLocation(buildingInstance));

        require(unitTeam == tileTeam, "LongbowFactory: Unit does not belong to factory's team");

        ds.getDispatcher().dispatch(abi.encodeCall(Actions.CRAFT, (buildingInstance)));
    }

    function construct(Game ds, bytes24, /*buildingKind*/ bytes24, /*mobileUnitID*/ bytes memory coordsEncoded)
        public
        override
    {
        State state = ds.getState();

        // NOTE: Cannot set data in construct hook because it's fired off before owner set

        int16[4] memory coords = abi.decode(coordsEncoded, (int16[4]));
        bytes24 zoneID = Node.Zone(coords[0]);

        Team team = LibUtils.getTileTeam(state, zoneID, Node.Tile(coords[0], coords[1], coords[2], coords[3]));
        require(team != Team.NONE, "LongbowFactory: Tile does not belong to a team");

        TeamState memory teamState =
            LibTeamState.decodeTeamState(uint256(state.getData(zoneID, LibUtils.getTeamStateKey(team))));

        require(teamState.hasLongbow, "LongbowFactory: Team does not have longbow blueprint");
    }
}
