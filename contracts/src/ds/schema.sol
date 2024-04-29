// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {State, CompoundKeyEncoder, CompoundKeyDecoder} from "./IState.sol";

interface Rel {
    function Owner() external;
    function Location() external;
    function Biome() external;
    function FacingDirection() external;
    function Balance() external;
    function Equip() external;
    function Is() external;
    function Supports() external;
    function Implementation() external;
    function Material() external;
    function Input() external;
    function Output() external;
    function Has() external;
    function Combat() external;
    function CombatAttacker() external;
    function CombatDefender() external;
    function IsFinalised() external;
    function HasTask() external;
    function HasQuest() external;
    function ID() external;
    function HasBlockNum() external;
    function Parent() external;
}

interface Kind {
    function ClientPlugin() external;
    function Extension() external;
    function Player() external;
    function ZonedPlayer() external;
    function MobileUnit() external;
    function Bag() external;
    function Tile() external;
    function BuildingKind() external;
    function Building() external;
    function Atom() external;
    function Item() external;
    function CombatSession() external;
    function Hash() external;
    function BlockNum() external;
    function Quest() external;
    function Task() external;
    function ID() external;
    function OwnedToken() external;
    function Zone() external;
    function GameSettings() external;
}

enum BuildingCategory {
    NONE,
    BLOCKER,
    EXTRACTOR,
    ITEM_FACTORY,
    CUSTOM,
    DISPLAY,
    BILLBOARD
}

library Node {
    function BuildingKind(string memory name, BuildingCategory category) internal pure returns (bytes24) {
        uint32 id = uint32(uint256(keccak256(abi.encodePacked("building/", name))));
        return BuildingKind(id, category);
    }
    
    function BuildingKind(uint64 id, BuildingCategory category) internal pure returns (bytes24) {
        return CompoundKeyEncoder.BYTES(
            Kind.BuildingKind.selector, bytes20(abi.encodePacked(uint32(0), id, uint64(category)))
        );
    }

    function Zone(int16 id) internal pure returns (bytes24) {
        require(id >= 0, "InvalidZoneID");
        return CompoundKeyEncoder.UINT64(Kind.Zone.selector, uint16(id));
    }
}

library Schema {
    function getImplementation(State state, bytes24 customizableThing) internal view returns (address) {
        (bytes24 contractNode,) = state.get(Rel.Implementation.selector, 0x0, customizableThing);
        return address(uint160(uint192(contractNode)));
    }
}