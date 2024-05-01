// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Script, console} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {IERC20Mintable} from "@latticexyz/world-modules/src/modules/erc20-puppet/IERC20Mintable.sol";
import {StoreSwitch} from "@latticexyz/store/src/StoreSwitch.sol";

import {SkyPoolConfig, MatchIndexToEntity, MatchSky} from "../src/codegen/index.sol";

import {IWorld} from "../src/codegen/world/IWorld.sol";
import {IBase} from "downstream/IBase.sol";
import {IZone} from "downstream/IZone.sol";

import {Game} from "../src/ds/IGame.sol";
import {State} from "../src/ds/IState.sol";
import {Schema, Node, BuildingCategory} from "../src/ds/Schema.sol";

import {TurfWars} from "../src/TurfWars.sol";
import {Helper} from "../src/Helper.sol";

using Schema for State;

contract InitTurfWars is Script {
    function setUp() public {}

    function run() public {
        Game ds = Game(vm.envAddress("DS_GAME_ADDR"));
        State state = ds.getState();
        int16 zoneKey = int16(vm.envInt("DS_ZONE"));

        string memory deployInfoPath = string(abi.encodePacked("./out/deploy-", vm.envString("DS_NETWORK"), ".json"));

        TurfWars turfWars;

        // Get existing TurfWars contract
        if (vm.exists(deployInfoPath)) {
            string memory deployJson = vm.readFile(deployInfoPath);
            turfWars = TurfWars(payable(vm.parseJsonAddress(deployJson, ".turfWars")));
        }

        IWorld world = IWorld(vm.envAddress("SS_GAME_ADDR"));
        StoreSwitch.setStoreAddress(address(world));

        // Get the orb token address
        IERC20Mintable orbToken = IERC20Mintable(SkyPoolConfig.getOrbToken());
        console.log("Orb Token Address: %s", address(orbToken));

        // Base building handle
        IBase baseBuilding = IBase(address(state.getImplementation(Node.BuildingKind("TW Base", BuildingCategory.CUSTOM))));
        require(address(baseBuilding) != address(0), "Base Building not found");
        console.log("Base Building Address: %s", address(baseBuilding));

        IZone zoneImpl = IZone(address(state.getImplementation(Node.Zone(zoneKey))));
        require(address(zoneImpl) != address(0), "Zone implementation not found");

        // ---- Downstream
        uint256 dsDeployKey = vm.envUint("DS_DEPLOY_KEY");
        vm.startBroadcast(dsDeployKey);

        // Deploy TurfWars contract if it hasn't been deployed before

        if (address(turfWars) == address(0)) {
            console.log("Deploying TurfWars contract");
            turfWars = (new TurfWars){value: 0.05 ether}(ds, world, orbToken, baseBuilding, zoneImpl);
        } else {
            console.log("Skipping deploy of TurfWars contract. Already deployed.");
        }
        
        {
            bytes32 firstMatchInWindow = Helper.findFirstMatchInWindow(SkyPoolConfig.getWindow());
            require(firstMatchInWindow != 0, "No match found in window");
            console.log("First Match in Window: %x", uint32(uint256(firstMatchInWindow >> 224)));

            address dsDeployAddr = vm.addr(dsDeployKey);

            // TODO: Don't reinit if addresses etc are the same
            baseBuilding.init(dsDeployAddr, address(world), address(turfWars), firstMatchInWindow);
        }

        vm.stopBroadcast();

        // ---- Sky Strife
        uint256 ssDeployKey = vm.envUint("SS_DEPLOY_KEY");
        vm.startBroadcast(ssDeployKey);

        if (keccak256(abi.encodePacked(vm.envString("DS_NETWORK"))) == keccak256(abi.encodePacked("local"))) {
            address ssDeployAddr = vm.addr(ssDeployKey);
            console.log("Minting 10k ORB for TurfWars and SS deployer");
            orbToken.mint(address(turfWars), 10_000 ether);
            orbToken.mint(address(ssDeployAddr), 10_000 ether);
        } else if (keccak256(abi.encodePacked(vm.envString("DS_NETWORK"))) == keccak256(abi.encodePacked("garnet"))) {
            console.log("Topping up TurfWars contract with orbs");
            // Top up the TurfWars contract with 500 ORB
            //orbToken.transfer(address(turfWars), 500 ether);
        }
        console.log("TurfWars balance: %s", address(turfWars).balance);

        vm.stopBroadcast();

        // -- Write deploy info
        // https://book.getfoundry.sh/cheatcodes/serialize-json
        string memory o = "key";
        vm.serializeAddress(o, "orbToken", address(orbToken));
        // vm.serializeBytes32(o, "firstMatchInWindow", firstMatchInWindow);
        vm.serializeAddress(o, "turfWars", address(turfWars));
        
        string memory newDeployJson = vm.serializeAddress(o, "zoneImpl", address(zoneImpl));
        
        vm.writeJson(newDeployJson, deployInfoPath);
    }
}
