// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import { MatchRanking, MatchPlayer} from "./codegen/index.sol";
import { IBattleBoy } from "downstream/IBattleBoy.sol";
import { IJudgeBuilding } from "downstream/IJudgeBuilding.sol";
import { Game } from "ds/IGame.sol";
import { IWorld } from "./codegen/world/IWorld.sol";
import { IERC20Mintable } from "@latticexyz/world-modules/src/modules/erc20-puppet/IERC20Mintable.sol";
import { StoreSwitch } from "@latticexyz/store/src/StoreSwitch.sol";
import { ITurfWars } from "downstream/ITurfWars.sol";

// import { console } from "forge-std/console.sol";

contract TurfWars is ITurfWars {
    Game public ds;
    IWorld public  world;
    IERC20Mintable public orbToken; 
    IBattleBoy public battleBoy;
    IJudgeBuilding public judgeBuilding;
    ITurfWars public turfWars;

    // -- Might need these if I have to buy the season pass from this contract
    fallback () external payable {}
    receive () external payable {}

    constructor(Game _ds, IWorld _world, IERC20Mintable _orbToken, IBattleBoy _battleBoy, IJudgeBuilding _judgeBuilding) payable {
        ds = _ds;
        world = _world;
        orbToken = _orbToken;
        battleBoy = _battleBoy;
        judgeBuilding = _judgeBuilding;
        
        StoreSwitch.setStoreAddress(address(world));
        world.buySeasonPass{value: msg.value}(address(this));
    }

    function startBattle(string memory name, bytes32 firstMatchInWindow, bytes32 matchID, bytes32 level) public {
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

    function isAddressWinner(address playerAddress, bytes32 matchEntity) public view returns (bool) {
        bytes32 playerEntity = MatchPlayer.get(matchEntity, playerAddress);
        require(playerEntity != 0, "player not registered for match");
        return getWinningPlayer(matchEntity) == playerEntity;
    }

}