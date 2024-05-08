// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MatchRanking, MatchPlayer, MatchPlayers} from "./codegen/index.sol";
import {IBase} from "downstream/IBase.sol";
import {IZone} from "downstream/IZone.sol";
import {Game} from "ds/IGame.sol";
import {IWorld} from "./codegen/world/IWorld.sol";
import {IERC20Mintable} from "@latticexyz/world-modules/src/modules/erc20-puppet/IERC20Mintable.sol";
import {StoreSwitch} from "@latticexyz/store/src/StoreSwitch.sol";
import {ITurfWars} from "downstream/ITurfWars.sol";

// import { console } from "forge-std/console.sol";

contract TurfWars is ITurfWars, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    Game public ds;
    IWorld public world;
    IERC20Mintable public orbToken;
    IBase public baseBuilding;

    // -- Might need these if I have to buy the season pass from this contract
    fallback() external payable {}
    receive() external payable {}

    modifier onlyBaseBuilding() {
        require(msg.sender == address(baseBuilding), "TurfWars: Only base building can call this function");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(Game _ds, IWorld _world, IERC20Mintable _orbToken, IBase _baseBuilding) public initializer {
        __Ownable_init(); //sets owner to msg.sender
        __UUPSUpgradeable_init();

        ds = _ds;
        world = _world;
        orbToken = _orbToken;
        baseBuilding = _baseBuilding;

        StoreSwitch.setStoreAddress(address(world));
    }

    function setBaseBuilding(IBase _baseBuilding) public onlyOwner {
        baseBuilding = _baseBuilding;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // -------------- //

    function withdrawFunds(address to, uint256 amount) public onlyOwner {
        payable(to).transfer(amount);
    }

    function withdrawOrbs(address to, uint256 amount) public onlyOwner {
        orbToken.transfer(to, amount);
    }

    function buySeasonPass() public payable onlyOwner {
        world.buySeasonPass{value: msg.value}(address(this));
    }

    function startBattle(string memory name, bytes32 firstMatchInWindow, bytes32 matchID, bytes32 level) public onlyBaseBuilding {
        world.createMatch(name, firstMatchInWindow, matchID, level);
        world.copyMap(matchID);
    }

    function getWinningPlayer(bytes32 matchEntity) public view returns (bytes32) {
        bytes32[] memory ranking = MatchRanking.get(matchEntity);
        if (ranking.length > 0) {
            return ranking[0];
        }
        return bytes32(0);
    }

    function hasAnyPlayerJoinedMatch(bytes32 matchEntity) public view returns (bool) {
        return MatchPlayers.length(matchEntity) > 0;
    }

    function isAddressWinner(address playerAddress, bytes32 matchEntity) public view returns (bool) {
        bytes32 playerEntity = MatchPlayer.get(matchEntity, playerAddress);
        require(playerEntity != 0, "player not registered for match");
        return getWinningPlayer(matchEntity) == playerEntity;
    }
}
