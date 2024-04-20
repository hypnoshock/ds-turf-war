// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { IWorld } from "../src/codegen/world/IWorld.sol";
import { StoreSwitch } from "@latticexyz/store/src/StoreSwitch.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SkyPoolConfig } from "../src/codegen/index.sol";
import { IERC20Mintable } from "@latticexyz/world-modules/src/modules/erc20-puppet/IERC20Mintable.sol";
import { Game } from "ds/IGame.sol";
import { State } from "ds/IState.sol";
import { Schema, Node, BuildingCategory } from "../src/ds/Schema.sol";
import { IBattleBoy } from "downstream/IBattleBoy.sol";

using Schema for State;

contract GetOrbAddress is Script {

  function run() external {
    uint256 ssDeployKey = vm.envUint("SS_DEPLOY_KEY");
    address ssDeployAddr = vm.addr(ssDeployKey);

    IWorld world = IWorld(vm.envAddress("SS_GAME_ADDR"));
    StoreSwitch.setStoreAddress(address(world));

    // Battle building handle
    Game ds = Game(vm.envAddress("DS_GAME_ADDR"));
    State state = ds.getState();
    bytes24 battleBuildingKind = Node.BuildingKind("Battle", BuildingCategory.CUSTOM);
    IBattleBoy battleBoy = IBattleBoy(state.getImplementation(battleBuildingKind));
    address turfWars = address(battleBoy.turfWars());

    IERC20Mintable token = IERC20Mintable(SkyPoolConfig.getOrbToken());
    console.log("Orb Token Address: %s", address(token));

    uint256 adminBal = token.balanceOf(ssDeployAddr) / 10 ** 18;
    uint256 buildingBal = token.balanceOf(turfWars) / 10 ** 18;
    console.log("Admin Bal: %s", adminBal);
    console.log("TurfWars Orb Bal: %s", buildingBal);
  }
}