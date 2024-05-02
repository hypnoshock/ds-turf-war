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

uint constant TW_ORB_POOL_AMOUNT = 500 ether;

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

        console.log("Setting Sky Strife world address");
        IWorld world = IWorld(vm.envAddress("SS_GAME_ADDR"));
        StoreSwitch.setStoreAddress(address(world));

        // Get the orb token address
        console.log("Getting Orb Token Address");
        IERC20Mintable orbToken = IERC20Mintable(SkyPoolConfig.getOrbToken());
        console.log("Orb Token Address: %s", address(orbToken));
        {
            address ssDeployAddr = vm.addr(vm.envUint("SS_DEPLOY_KEY"));
            uint256 deployerOrbBal = orbToken.balanceOf(ssDeployAddr);
            console.log("Deployer orbs: %s", deployerOrbBal); // 10 ** 18
        }

        // Base building handle
        IBase baseBuilding = IBase(address(state.getImplementation(Node.BuildingKind("TW Base", BuildingCategory.CUSTOM))));
        require(address(baseBuilding) != address(0), "Base Building not found");
        console.log("Base Building Address: %s", address(baseBuilding));

        IZone zoneImpl = IZone(address(state.getImplementation(Node.Zone(zoneKey))));
        require(address(zoneImpl) != address(0), "Zone implementation not found");

        // ---- Downstream
        uint256 dsDeployKey = vm.envUint("DS_DEPLOY_KEY");

        // Deploy TurfWars contract if it hasn't been deployed before

        if (address(turfWars) == address(0)) {
            vm.startBroadcast(dsDeployKey);
            console.log("Deploying TurfWars contract");
            turfWars = new TurfWars(ds, world, orbToken, baseBuilding, zoneImpl);
            if (keccak256(abi.encodePacked(vm.envString("DS_NETWORK"))) == keccak256(abi.encodePacked("local"))) {
                turfWars.buySeasonPass{value: 0.05 ether}();
            } else if (keccak256(abi.encodePacked(vm.envString("DS_NETWORK"))) == keccak256(abi.encodePacked("garnet"))) {
                // -- Cannot buy pass on Garnet as minting period is over
                console.log("Skipping buySeasonPass on Garnet");
                // turfWars.buySeasonPass{value: 0.03 ether}();
            }
            vm.stopBroadcast();

        } else {
            console.log("Skipping deploy of TurfWars contract. Already deployed.");
            // TODO: Update baseBuilding / zoneImpl on turfWars contract if changed
        }
        
        {
            bytes32 firstMatchInWindow = Helper.findFirstMatchInWindow(SkyPoolConfig.getWindow());
            require(firstMatchInWindow != 0, "No match found in window");
            console.log("First Match in Window: %x", uint32(uint256(firstMatchInWindow >> 224)));

            address dsDeployAddr = vm.addr(dsDeployKey);

            if (baseBuilding.owner() == address(0)) {
                vm.startBroadcast(dsDeployKey);
                console.log("Initializing Base Building");
                baseBuilding.init(dsDeployAddr, address(world), address(turfWars), firstMatchInWindow);
                vm.stopBroadcast();
            } else {
                console.log("Base Building already initialized - Updating any changes");
                if (address(baseBuilding.world()) != address(world)) {
                    vm.startBroadcast(dsDeployKey);
                    baseBuilding.setSkyStrifeWorld(address(world));
                    vm.stopBroadcast();
                }
                if (address(baseBuilding.turfWars()) != address(turfWars)) {
                    vm.startBroadcast(dsDeployKey);
                    baseBuilding.setTurfWars(address(turfWars));
                    vm.stopBroadcast();
                }
                if (baseBuilding.firstMatchInWindow() != firstMatchInWindow) {
                    vm.startBroadcast(dsDeployKey);
                    baseBuilding.setFirstMatchInWindow(firstMatchInWindow);
                    vm.stopBroadcast();
                }
            }
        }

        // ---- Sky Strife
        uint256 ssDeployKey = vm.envUint("SS_DEPLOY_KEY");

        if (keccak256(abi.encodePacked(vm.envString("DS_NETWORK"))) == keccak256(abi.encodePacked("local"))) {
            vm.startBroadcast(ssDeployKey);
            address ssDeployAddr = vm.addr(ssDeployKey);
            console.log("Minting 10k ORB for TurfWars and SS deployer");
            orbToken.mint(address(turfWars), 10_000 ether);
            orbToken.mint(address(ssDeployAddr), 10_000 ether);
            vm.stopBroadcast();
        } else if (keccak256(abi.encodePacked(vm.envString("DS_NETWORK"))) == keccak256(abi.encodePacked("garnet"))) {
            console.log("Topping up TurfWars contract with orbs");

            address ssDeployAddr = vm.addr(vm.envUint("SS_DEPLOY_KEY"));

            // Top up the TurfWars contract with ORBs
            uint256 requiredOrbs = TW_ORB_POOL_AMOUNT - orbToken.balanceOf(address(turfWars));
            require(requiredOrbs <= orbToken.balanceOf(ssDeployAddr), "Deployer does not have enough orbs to top up TurfWars contract");
            
            if (requiredOrbs > 0) {
                vm.startBroadcast(ssDeployKey);
                orbToken.transfer(address(turfWars), requiredOrbs);
                vm.stopBroadcast();
            }

            console.log("Deployer orbs: %s", orbToken.balanceOf(ssDeployAddr));
            console.log("TurfWars orbs: %s", orbToken.balanceOf(address(turfWars)));
            console.log("TurfWars ETH balance: %s", address(turfWars).balance);
        }

        

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
