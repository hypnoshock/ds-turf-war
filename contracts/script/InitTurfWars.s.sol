// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Script, console} from "forge-std/Script.sol";
import "forge-std/console.sol";
import { IERC20Mintable } from "@latticexyz/world-modules/src/modules/erc20-puppet/IERC20Mintable.sol";
import { StoreSwitch } from "@latticexyz/store/src/StoreSwitch.sol";

import { IWorld } from "../src/codegen/world/IWorld.sol";
import { SkyPoolConfig } from "../src/codegen/index.sol";
import { IBattleBoy } from "downstream/IBattleBoy.sol";
import { IJudgeBuilding } from "downstream/IJudgeBuilding.sol";

import { Game } from "../src/ds/IGame.sol";
import { State } from "../src/ds/IState.sol";
import { Schema, Node, BuildingCategory } from "../src/ds/Schema.sol";

using Schema for State;

contract InitTurfWars is Script {
    function setUp() public {}

    function run() public {
        uint256 dsDeployKey = vm.envUint("DS_DEPLOY_KEY");
        uint256 ssDeployKey = vm.envUint("SS_DEPLOY_KEY");
        address ssDeployAddr = vm.addr(ssDeployKey);
        bytes32 firstMatchInWindow = vm.envBytes32("FIRST_MATCH_IN_WINDOW");
                
        Game ds = Game(vm.envAddress("DS_GAME_ADDR"));
        State state = ds.getState();

        IWorld world = IWorld(vm.envAddress("SS_GAME_ADDR"));
        StoreSwitch.setStoreAddress(address(world));

        // Get the orb token address
        IERC20Mintable orbToken = IERC20Mintable(SkyPoolConfig.getOrbToken());
        console.log("Orb Token Address: %s", address(orbToken));

        // Battle building handle
        bytes24 battleBuildingKind = Node.BuildingKind("Battle", BuildingCategory.CUSTOM);
        IBattleBoy battleBuilding = IBattleBoy(address(state.getImplementation(battleBuildingKind)));
        require(address(battleBuilding) != address(0), "Battle Building not found");
        console.log("Battle Building Address: %s", address(battleBuilding));

        // Judge building handle
        bytes24 judgeBuildingKind = Node.BuildingKind("Judge", BuildingCategory.CUSTOM);
        IJudgeBuilding judgeBuilding = IJudgeBuilding(address(state.getImplementation(judgeBuildingKind))); 
        require(address(judgeBuilding) != address(0), "Judge Building not found");
        console.log("Judge Building Address: %s", address(judgeBuilding));      

        vm.startBroadcast(dsDeployKey);

        battleBuilding.setJudgeBuilding(address(judgeBuilding));
        battleBuilding.setFirstMatchInWindow(firstMatchInWindow);

        judgeBuilding.setGame(address (ds));
        // judgeBuilding.setBuildingInstance(buildingInstance);

        vm.stopBroadcast();

        vm.startBroadcast(ssDeployKey);
        orbToken.transfer(address(battleBuilding), 500 ether);

        vm.stopBroadcast();
    }
}
