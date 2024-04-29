// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Script, console} from "forge-std/Script.sol";
import "forge-std/console.sol";
import { IERC20Mintable } from "@latticexyz/world-modules/src/modules/erc20-puppet/IERC20Mintable.sol";
import { StoreSwitch } from "@latticexyz/store/src/StoreSwitch.sol";

import { SkyPoolConfig, MatchIndexToEntity, MatchSky } from "../src/codegen/index.sol";

import { IWorld } from "../src/codegen/world/IWorld.sol";
import { IBase } from "downstream/IBase.sol";
import { IZone } from "downstream/IZone.sol";

import { Game } from "../src/ds/IGame.sol";
import { State } from "../src/ds/IState.sol";
import { Schema, Node, BuildingCategory } from "../src/ds/Schema.sol";

import { TurfWars } from "../src/TurfWars.sol";
import { Helper } from "../src/Helper.sol";

using Schema for State;

contract InitTurfWars is Script {
    function setUp() public {}

    function run() public {
        uint256 dsDeployKey = vm.envUint("DS_DEPLOY_KEY");
        address dsDeployAddr = vm.addr(dsDeployKey);
        uint256 ssDeployKey = vm.envUint("SS_DEPLOY_KEY");
        address ssDeployAddr = vm.addr(ssDeployKey);
                
        Game ds = Game(vm.envAddress("DS_GAME_ADDR"));
        State state = ds.getState();
        int16 zoneKey = int16(vm.envInt("DS_ZONE"));

        IWorld world = IWorld(vm.envAddress("SS_GAME_ADDR"));
        StoreSwitch.setStoreAddress(address(world));

        // Get the orb token address
        IERC20Mintable orbToken = IERC20Mintable(SkyPoolConfig.getOrbToken());
        console.log("Orb Token Address: %s", address(orbToken));

        // Base building handle
        bytes24 baseBuildingKind = Node.BuildingKind("Base", BuildingCategory.CUSTOM);
        IBase baseBuilding = IBase(address(state.getImplementation(baseBuildingKind)));
        require(address(baseBuilding) != address(0), "Base Building not found");
        console.log("Base Building Address: %s", address(baseBuilding));

        bytes32 firstMatchInWindow = Helper.findFirstMatchInWindow(SkyPoolConfig.getWindow());
        require (firstMatchInWindow != 0, "No match found in window");
        console.log("First Match in Window: %x", uint32(uint256(firstMatchInWindow >> 224)));

        IZone zoneImpl = IZone(address(state.getImplementation(Node.Zone(zoneKey))));
        require (address(zoneImpl) != address(0), "Zone implementation not found");

        // -- Downstream 
        vm.startBroadcast(dsDeployKey);

        TurfWars turfWars = (new TurfWars){value: 0.05 ether}(ds, world, orbToken, baseBuilding, zoneImpl);
        console.log("TurfWars balance: %s", address(turfWars).balance);

        baseBuilding.init(
            dsDeployAddr,
            address(world),
            address(turfWars),
            firstMatchInWindow
        );

        vm.stopBroadcast();

        // -- Sky Strife
        vm.startBroadcast(ssDeployKey);
        orbToken.mint(address(turfWars), 10_000 ether);
        orbToken.mint(address(ssDeployAddr), 10_000 ether);
        
        // On Redstone cannot mind obviously so transfer from deployer
        //orbToken.transfer(address(turfWars), 500 ether);

        vm.stopBroadcast();
    }

}
