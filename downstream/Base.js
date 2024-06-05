import ds from "downstream";

const nullBytes24 = `0x${"00".repeat(24)}`;
const nullBytes32 = `0x${"00".repeat(32)}`;
const BLOCK_TIME_SECS = 2;
const TEAM_A = "team1";
const TEAM_B = "team2";
const DATA_BATTLE_START_BLOCK = "battleStartBlock";
const func = ds;
const networkEndpoint = ds.config.networkEndpoint;
const gameContractAddr = getGameContractAddr(ds.config.networkName);

let battleState = {
  battalionState: [],
  isFinished: false,
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

let lastBlock = 0;
let isNewBlock = false;

export default async function update(state, block) {
  if (block !== lastBlock) {
    lastBlock = block;
    isNewBlock = true;
  } else {
    isNewBlock = false;
  }

  //   const buildings = state.world?.buildings || [];
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

  // DEBUG
  // console.log("ds", ds);
  // console.log("implementationAddr", implementationAddr);
  // console.log("selectedBuilding", selectedBuilding);
  // const winner = getData(selectedBuilding, getTileWinnerKey(selectedBuilding));
  // console.log("matchID", matchID);
  // console.log("winner", winner);
  console.log("battleState", battleState);

  //--  Fetch the latest state

  if (isNewBlock) {
    fetchBattleState(selectedBuilding, block);
  }

  // players are unit ids
  const { teamAPlayers, teamBPlayers } = getTurfWarsState(state, state.world);

  const tileWinnerKey = getTileWinnerKey(selectedBuilding.location.tile.id);
  const winnerUnitId = getDataBytes24(state.world, tileWinnerKey);
  const tileTeam = getTeam(teamAPlayers, teamBPlayers, winnerUnitId);
  const playerTeam = getTeam(teamAPlayers, teamBPlayers, mobileUnit.id);

  // The team that has claimed the tile will be on the defence
  const defenders = getSoldierCount(battleState, tileTeam);

  // Attackers are on the opposing team
  const attackers = getSoldierCount(
    battleState,
    tileTeam == TEAM_A ? TEAM_B : TEAM_A
  );

  const startBattle = () => {
    const payload = ds.encodeCall("function startBattle()", []);
    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, mobileUnit.id, payload],
    });
  };

  const continueBattle = () => {
    const payload = ds.encodeCall("function continueBattle()", []);
    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, mobileUnit.id, payload],
    });
  };

  const addSoldiers = (amount) => {
    const payload = ds.encodeCall("function addSoldiers(uint8)", [amount]);
    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, mobileUnit.id, payload],
    });
  };

  const claimWin = () => {
    const payload = ds.encodeCall("function claimWin()", []);
    const bagID = generateDevBagId(selectedBuilding.location.tile);
    console.log("bagID", bagID);
    const [toEquipSlot, toItemSlot] = getCompatibleOrEmptySlot(
      mobileUnit,
      "TW Hammer",
      1
    );
    ds.dispatch(
      {
        name: "BUILDING_USE",
        args: [selectedBuilding.id, mobileUnit.id, payload],
      },
      {
        name: "TRANSFER_ITEM_MOBILE_UNIT",
        args: [
          mobileUnit.id,
          [selectedBuilding.location.tile.id, mobileUnit.id],
          [0, toEquipSlot],
          [0, toItemSlot],
          nullBytes24,
          1, // Claim hammer
        ],
      },
      {
        name: "ZONE_USE",
        args: [
          mobileUnit.id,
          ds.encodeCall("function destroyTileBag(bytes24,bytes24,bytes24[])", [
            selectedBuilding.location.tile.id,
            bagID,
            [nullBytes24, nullBytes24, nullBytes24, nullBytes24], // The dev destroy bag action is mental - it uses the length of the array to determine slot count. Doesn't care about contents!
          ]),
        ],
      }
    );
  };

  const battleStartBlock = getDataInt(
    selectedBuilding,
    DATA_BATTLE_START_BLOCK
  );

  let html = `
    <p>defenders: ${defenders}</p>
    <p>attackers: ${attackers}</p>
    <p>battle finished: ${battleState.isFinished}</p>
  `;
  const buttons = [];

  if (battleStartBlock === 0) {
    buttons.push({
      text: "Start Battle",
      type: "action",
      action: startBattle,
      disabled: false,
    });
  } else {
    html += `<p>Battle started at block: ${battleStartBlock}</p>`;
    // html += `<p>Time remaining until attacker can claim win by default</p><h3>${formatTime(remainingTimeMs)}</h3>`;
  }

  if (battleState.isFinished) {
    if (defenders == 0 || attackers == 0) {
      buttons.push({
        text: "Claim Win",
        type: "action",
        action: claimWin,
        disabled: false,
      });
    } else {
      buttons.push({
        text: "Continue Battle",
        type: "action",
        action: continueBattle,
        disabled: false,
      });
    }
  }

  buttons.push({
    text: "Add 1 soldier",
    type: "action",
    action: () => {
      addSoldiers(1);
    },
    disabled: false,
  });

  buttons.push({
    text: "Add 5 soldiers",
    type: "action",
    action: () => {
      addSoldiers(5);
    },
    disabled: false,
  });

  return {
    version: 1,
    components: [
      {
        id: "TW-Base",
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

// ---- State fetching

function fetchBattleState(building, block) {
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
            "function getBattleState(address,bytes24,uint256)",
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
        console.error("Unable to retrieve battle state", data.error);
        return;
      }

      if (!data.result) {
        console.error("No result from battle state call");
        console.log("data: ", data);
        console.log("endpoint: ", networkEndpoint);
        return;
      }

      const [battalionStates, isFinished] = ds.abiDecode(
        ["(uint8,uint8,uint8[5],uint8[3])[]", "bool"],
        data.result
      );

      battleState = {
        battalionState: battalionStates.map((battalionState, idx) => {
          const [_teamId, soldierCount, weapons, defence] = battalionState;
          // TODO: Currently using idx to determine team key, this is not safe when we have more than 2 players
          const teamKey = idx === 0 ? TEAM_A : TEAM_B;
          return { teamKey, soldierCount, weapons, defence };
        }),
        isFinished,
      };
    });
}

// ---- turf wars helper functions ----

function getTurfWarsState(state, zone) {
  if (!zone) {
    throw new Error("Zone not found");
  }
  const gameState = getDataInt(zone, "gameState");
  const startBlock = getDataInt(zone, "startBlock");
  const endBlock = getDataInt(zone, "endBlock");
  const teamALength = getDataInt(zone, TEAM_A + "Length");
  const teamBLength = getDataInt(zone, TEAM_B + "Length");

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

  return {
    gameState,
    startBlock,
    endBlock,
    startBlock,
    teamALength,
    teamBLength,
    teamAPlayers,
    teamBPlayers,
  };
}

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

function getSoldierCount(battleState, teamKey) {
  const battalionState = battleState.battalionState.find(
    (t) => t.teamKey === teamKey
  );
  if (!battalionState) {
    return 0;
  }
  return battalionState.soldierCount;
}

// ---- helper functions ----

const getBuildingsByType = (buildingsArray, type) => {
  return buildingsArray.filter((building) =>
    building.kind?.name?.value.toLowerCase().includes(type)
  );
};

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

function formatTime(timeInMs) {
  let seconds = Math.floor(timeInMs / 1000);
  let minutes = Math.floor(seconds / 60);
  let hours = Math.floor(minutes / 60);

  seconds %= 60;
  minutes %= 60;

  // Pad each component to ensure two digits
  let formattedHours = String(hours).padStart(2, "0");
  let formattedMinutes = String(minutes).padStart(2, "0");
  let formattedSeconds = String(seconds).padStart(2, "0");

  return `${formattedMinutes}:${formattedSeconds}`;
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

// -- Match Data

function getTileWinnerKey(tileId) {
  return tileId + "_winner";
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
