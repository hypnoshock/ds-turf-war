import ds from "downstream";

const nullBytes24 = `0x${"00".repeat(24)}`;

const TEAM_A = "team1";
const TEAM_B = "team2";
const BLOCK_TIME_SECS = 2;
const GAME_STATE_NOT_STARTED = 0;
const GAME_STATE_IN_PROGRESS = 1;
const GAME_STATE_FINISHED = 2;

const SLINGSHOT = 1;
const LONGBOW = 2;
const GUN = 3;

// const HAMMER_SPAWN_EQUIP_SLOT = 0;
// const SOLDIER_SPAWN_EQUIP_SLOT = 1;
const PERSON_SPAWN_EQUIP_SLOT = 2;

// const SOLDIER_DEPOSIT_BAG_EQUIP_SLOT = 0;
const PERSON_DEPOSIT_BAG_EQUIP_SLOT = 1;

const networkEndpoint = ds.config.networkEndpoint;
const gameContractAddr = getGameContractAddr(ds.config.networkName);

let lastBlock = 0;
let isNewBlock = false;
let personState = {
  team: 0,
  count: 0,
};
let researchState = {
  researchedTech: 0,
  percent: 0,
};

function getGameContractAddr(networkName) {
  switch (networkName) {
    case "hexwoodlocal":
      return "0xF8311e28c658003929A7c1218fb8E44cE7A814DE";
    case "redstone":
      return "0x0";
    default:
      throw "Turf Wars: Unknown network: " + networkName;
  }
}

export default async function update(state, block) {
  const mobileUnit = getMobileUnit(state);
  const selectedTile = getSelectedTile(state);
  const selectedBuilding =
    selectedTile && getBuildingOnTile(state, selectedTile);

  if (!selectedBuilding || !mobileUnit) {
    return {
      version: 1,
      components: [],
    };
  }

  // console.log(selectedBuilding);

  const { teamAPlayers, teamBPlayers } = getTurfWarsState(
    state,
    block,
    state.world
  );
  const tileWinnerKey = getTileWinnerKey(selectedBuilding.location.tile.id);
  const winnerUnitId = getDataBytes24(state.world, tileWinnerKey);
  const tileTeam = getTeam(teamAPlayers, teamBPlayers, winnerUnitId);

  if (block !== lastBlock) {
    lastBlock = block;
    isNewBlock = true;
  } else {
    isNewBlock = false;
  }

  if (isNewBlock) {
    fetchPersonState(selectedBuilding, block, tileTeam);
    fetchResearchState(selectedBuilding);
  }

  const addPerson = (amount) => {
    const [fromEquipSlot, fromItemSlot] = getItemSlotWithBalance(
      mobileUnit,
      "TW Person"
    );
    const [toEquipSlot, toItemSlot] = [PERSON_DEPOSIT_BAG_EQUIP_SLOT, 0];

    ds.dispatch(
      {
        name: "TRANSFER_ITEM_MOBILE_UNIT",
        args: [
          mobileUnit.id,
          [mobileUnit.id, selectedBuilding.id],
          [fromEquipSlot, toEquipSlot],
          [fromItemSlot, toItemSlot],
          nullBytes24, // Used to make a new bag on the fly
          amount,
        ],
      },
      {
        name: "BUILDING_USE",
        args: [
          selectedBuilding.id,
          mobileUnit.id,
          ds.encodeCall("function addPerson()", [amount]),
        ],
      }
    );
  };

  const removePerson = (amount) => {
    const [fromEquipSlot, fromItemSlot] = [PERSON_SPAWN_EQUIP_SLOT, 0];
    const [toEquipSlot, toItemSlot] = getCompatibleOrEmptySlot(
      mobileUnit,
      "TW Person",
      amount
    );

    // The temp bag person items get spawned into
    const spawnBagID = generateDevBagId(
      mobileUnit.nextLocation.tile,
      PERSON_SPAWN_EQUIP_SLOT
    );

    ds.dispatch(
      {
        name: "BUILDING_USE",
        args: [
          selectedBuilding.id,
          mobileUnit.id,
          ds.encodeCall("function removePerson(uint16)", [amount]),
        ],
      },
      {
        name: "TRANSFER_ITEM_MOBILE_UNIT",
        args: [
          mobileUnit.id,
          [mobileUnit.nextLocation.tile.id, mobileUnit.id], // from entity, to entity
          [fromEquipSlot, toEquipSlot],
          [fromItemSlot, toItemSlot],
          nullBytes24, // Used to make a new bag on the fly
          amount,
        ],
      },
      {
        name: "ZONE_USE",
        args: [
          mobileUnit.id,
          ds.encodeCall(
            "function destroyTileBag(bytes24,bytes24,uint8,bytes24[])",
            [
              mobileUnit.nextLocation.tile.id, // Tile ID
              spawnBagID,
              fromEquipSlot,
              [nullBytes24, nullBytes24, nullBytes24, nullBytes24], // The dev destroy bag action is mental - it uses the length of the array to determine slot count. Doesn't care about contents!
            ]
          ),
        ],
      }
    );
  };

  const setResearch = (weapon) => {
    ds.dispatch({
      name: "BUILDING_USE",
      args: [
        selectedBuilding.id,
        mobileUnit.id,
        ds.encodeCall("function setResearchedTech(uint8)", [weapon]),
      ],
    });
  };

  let html = `
    <p>scientists: ${personState.count}</p>
  `;

  if (researchState.researchedTech != 0) {
    html += `
      <p>researching: ${getWeaponName(researchState.researchedTech)}</p>
      <p>progress: ${researchState.percent}%</p>
    `;
  }

  const buttons = [];

  buttons.push({
    text: "Add 1 person",
    type: "action",
    action: () => {
      addPerson(1);
    },
    disabled: false,
  });

  buttons.push({
    text: "Add 5 people",
    type: "action",
    action: () => {
      addPerson(5);
    },
    disabled: false,
  });

  buttons.push({
    text: "Remove 1 person",
    type: "action",
    action: () => {
      removePerson(1);
    },
    disabled: false,
  });

  buttons.push({
    text: "Remove 5 people",
    type: "action",
    action: () => {
      removePerson(5);
    },
    disabled: false,
  });

  buttons.push({
    text: "Research Slingshot",
    type: "action",
    action: () => {
      setResearch(SLINGSHOT);
    },
    disabled: false,
  });

  buttons.push({
    text: "Research Longbow",
    type: "action",
    action: () => {
      setResearch(LONGBOW);
    },
    disabled: false,
  });

  buttons.push({
    text: "Research Gun",
    type: "action",
    action: () => {
      setResearch(GUN);
    },
    disabled: false,
  });

  return {
    version: 1,
    components: [
      {
        id: "research-centre",
        type: "building",
        content: [
          {
            id: "default",
            type: "inline",
            html,
            buttons,
          },
        ],
      },
    ],
  };
}

// ---- helper functions ----

function getMobileUnit(state) {
  return state?.selected?.mobileUnit;
}

function getSelectedTile(state) {
  const tiles = state?.selected?.tiles || {};
  return tiles && tiles.length === 1 ? tiles[0] : undefined;
}

function getBuildingOnTile(state, tile) {
  return (state?.world?.buildings || []).find(
    (b) => tile && b.location?.tile?.id === tile.id
  );
}

function generateDevBagId(tile, equipSlot = 0) {
  // Generate the ID for the bag that will get created by the DEV_SPAWN_BAG action. We need this because
  // I wanted to generate it on the contract side but contract was over size limit!!

  // NOTE: the coords are encoded 2's complement int16's. If I tell the encoder they are int16 it will get an out of range error.
  const [z, q, r, s] = tile.coords;
  const bagKey256 = ds.keccak256(
    ds.abiEncode(
      ["string", "uint16", "uint16", "uint16", "uint16", "uint8"],
      ["devbag", z, q, r, s, equipSlot]
    )
  );
  // String manipulation instead of bitwise operations is icky but it works! :D
  const bagKey64 = BigInt(`0x${bagKey256.slice(-16)}`).toString(16);

  // Yes this is as horrendous as it looks
  return "0xb1c93f09000000000000000000000000" + bagKey64;
}

function getCompatibleOrEmptySlot(mobileUnit, itemName, quantity = 1) {
  // First try and find a slot that already has the item
  for (let bag of mobileUnit.bags) {
    for (let slot of bag.slots) {
      if (
        slot.item.name?.value === itemName &&
        slot.balance + quantity <= 100
      ) {
        console.log("Found compatible slot", bag.equipee.key, slot.key);
        return [bag.equipee.key, slot.key];
      }
    }
  }

  // Find first empty slot
  for (let bag of mobileUnit.bags) {
    if (bag.slots.length < 4) {
      // find the first unused key
      let slotKey = 0;
      while (bag.slots.some((s) => s.key === slotKey)) {
        slotKey++;
      }
      console.log("Found empty slot", bag.equipee.key, slotKey);
      return [bag.equipee.key, slotKey];
    }
  }

  throw "No compatible or empty slot found";
}

function getItemSlotWithBalance(mobileUnit, itemName, quantity = 1) {
  // First try and find a slot that already has the item
  for (let bag of mobileUnit.bags) {
    for (let slot of bag.slots) {
      if (slot.item.name?.value === itemName && slot.balance >= quantity) {
        console.log(
          "Found item in Unit's inventory",
          bag.equipee.key,
          slot.key
        );
        return [bag.equipee.key, slot.key];
      }
    }
  }

  throw "item not found in units inventory. itemName: " + itemName;
}

// -- Building Data

function getData(buildingInstance, key) {
  return getKVPs(buildingInstance)[key];
}

function getDataBool(buildingInstance, key) {
  var hexVal = getData(buildingInstance, key);
  return typeof hexVal === "string" ? parseInt(hexVal, 16) == 1 : false;
}

function getDataInt(buildingInstance, key) {
  var hexVal = getData(buildingInstance, key);
  return typeof hexVal === "string" ? parseInt(hexVal, 16) : 0;
}

function getDataBytes24(buildingInstance, key) {
  var hexVal = getData(buildingInstance, key);
  return typeof hexVal === "string" ? hexVal.slice(0, -16) : nullBytes24;
}

function getKVPs(buildingInstance) {
  return buildingInstance.allData.reduce((kvps, data) => {
    kvps[data.name] = data.value;
    return kvps;
  }, {});
}

// -- TW specific helper functions

function getTeamUnitAtIndex(zone, team, index) {
  return getDataBytes24(zone, `${team}Unit_${index}`);
}

function getTeam(teamAPlayers, teamBPlayers, playerId) {
  if (teamAPlayers.includes(playerId)) {
    return TEAM_A;
  } else if (teamBPlayers.includes(playerId)) {
    return TEAM_B;
  } else {
    return "";
  }
}

function getTileWinnerKey(tileId) {
  return tileId + "_winner";
}

function getWeaponName(weaponEnum) {
  switch (weaponEnum) {
    case SLINGSHOT:
      return "Sling Shot";
    case LONGBOW:
      return "Longbow";
    case GUN:
      return "Gun";
    default:
      return "Unknown";
  }
}

// ---- STATE ----

function fetchResearchState(building) {
  const buildingId = building.id;
  const buildingImplementationAddr =
    "0x" + building.kind.implementation.id.slice(-40);

  // Battle hasn't started, get initial state from DATA_INIT_STATE

  // else fetch the full state from the contract

  fetch(networkEndpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      method: "eth_call",
      params: [
        {
          to: buildingImplementationAddr,
          data: ds.encodeCall("function getResearchState(address,bytes24)", [
            gameContractAddr,
            buildingId,
          ]),
        },
        "latest",
      ],
      id: 1,
    }),
  })
    .then((response) => response.json())
    .then((data) => {
      if (data.error) {
        console.error("Unable to retrieve research state", data.error);
        return;
      }

      if (!data.result) {
        console.error("No result from research state call");
        console.log("data: ", data);
        console.log("endpoint: ", networkEndpoint);
        return;
      }

      const [researchStateRes] = ds.abiDecode(
        ["(uint256,int128)"],
        data.result
      );
      const [researchedTech, percent] = researchStateRes;

      researchState = {
        researchedTech: Number(researchedTech),
        percent: Number(percent >> 64n),
      };
    });
}

function fetchPersonState(building, block, teamKey) {
  const teamEnum = teamKey.replace("team", "");

  const buildingId = building.id;
  const buildingImplementationAddr =
    "0x" + building.kind.implementation.id.slice(-40);

  // Battle hasn't started, get initial state from DATA_INIT_STATE

  // else fetch the full state from the contract

  fetch(networkEndpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      method: "eth_call",
      params: [
        {
          to: buildingImplementationAddr,
          data: ds.encodeCall(
            "function getPersonStates(address,bytes24,uint256)",
            [gameContractAddr, buildingId, block]
          ),
        },
        "latest",
      ],
      id: 1,
    }),
  })
    .then((response) => response.json())
    .then((data) => {
      if (data.error) {
        console.error("Unable to retrieve person state", data.error);
        return;
      }

      if (!data.result) {
        console.error("No result from person state call");
        console.log("data: ", data);
        console.log("endpoint: ", networkEndpoint);
        return;
      }

      const [personStates] = ds.abiDecode(["(uint8,uint16)[]"], data.result);
      const [team, count] = personStates[teamEnum - 1];

      personState = {
        team,
        count,
      };
    });
}

// Copied from Zone.js
// ------------------------------------------------------- Turf Wars state

function getTurfWarsState(state, block, zone) {
  if (!zone) {
    throw new Error("Zone not found");
  }
  const prizePool = getDataInt(zone, "prizePool");
  const startBlock = getDataInt(zone, "startBlock");
  const endBlock = getDataInt(zone, "endBlock");
  const teamALength = getDataInt(zone, TEAM_A + "Length");
  const teamBLength = getDataInt(zone, TEAM_B + "Length");

  // Remaining time
  const nowBlock = block;
  const remainingBlocks = endBlock > nowBlock ? endBlock - nowBlock : 0;
  const remainingTimeMs = remainingBlocks * BLOCK_TIME_SECS * 1000;

  let gameState = getDataInt(zone, "gameState");
  if (remainingBlocks === 0 && gameState == GAME_STATE_IN_PROGRESS) {
    gameState = GAME_STATE_FINISHED;
  }

  const teamAPlayers = [];
  for (let i = 0; i < teamALength; i++) {
    const unitId = getTeamUnitAtIndex(zone, TEAM_A, i);
    teamAPlayers.push(unitId);
  }

  const teamBPlayers = [];
  for (let i = 0; i < teamBLength; i++) {
    const unitId = getTeamUnitAtIndex(zone, TEAM_B, i);
    teamBPlayers.push(unitId);
  }

  const dirtyTiles = [];
  const teamATiles = [];
  const teamBTiles = [];
  zone.allData.forEach((data) => {
    if (data.name.includes("_winner")) {
      const tileId = data.name.split("_")[0];
      dirtyTiles.push(tileId);
      if (
        !!teamAPlayers.some(
          (unitId) =>
            unitId.toLowerCase() ==
            data.value.slice(0, 24 * 2 + 2).toLowerCase()
        )
      ) {
        teamATiles.push(tileId);
      } else if (
        !!teamBPlayers.some(
          (unitId) =>
            unitId.toLowerCase() ==
            data.value.slice(0, 24 * 2 + 2).toLowerCase()
        )
      ) {
        teamBTiles.push(tileId);
      }
    }
  });

  return {
    prizePool,
    gameState,
    startBlock,
    endBlock,
    startBlock,
    teamALength,
    teamBLength,
    teamATiles,
    teamBTiles,
    teamAPlayers,
    teamBPlayers,
    remainingTimeMs,
    dirtyTiles,
  };
}
