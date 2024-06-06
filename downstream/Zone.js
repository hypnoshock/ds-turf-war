import ds from "downstream";

const nullBytes24 = `0x${"00".repeat(24)}`;
const nullBytes32 = `0x${"00".repeat(32)}`;

const TILE_ID_PREFIX = "0xe5a62ffc";
const TEAM_A = "team1";
const TEAM_B = "team2";
const BLOCK_TIME_SECS = 2;
const GAME_STATE_NOT_STARTED = 0;
const GAME_STATE_IN_PROGRESS = 1;
const GAME_STATE_FINISHED = 2;
const CLOCK_MSG = "Turf Wars ";
const LEFT_COUNTER_MSG = "TURF WARS! ";
const RIGHT_COUNTER_MSG = "_-`'´-";

export default async function update(state, block) {
  const zone = state.world;

  // console.log("Zone", zone);
  // const implementationAddr = zone.kind.implementation.id.slice(-40);
  // console.log("Judge implementationAddr", implementationAddr);

  const mapObj = [];

  const {
    prizePool,
    gameState,
    teamALength,
    teamBLength,
    teamATiles,
    teamBTiles,
    remainingTimeMs,
  } = getTurfWarsState(state, block, zone);

  // console.log("teamATiles", teamATiles);
  // console.log("teamAPlayers", teamAPlayers);

  const teamAScore = teamATiles.length;
  const teamBScore = teamBTiles.length;

  // unit plugin properties - unit color
  const unitMapObj = [];
  for (let i = 0; i < teamALength; i++) {
    const unitId = getTeamUnitAtIndex(zone, TEAM_A, i);
    const mobileUnit = state.world?.mobileUnits?.find(
      (unit) => unit.id === unitId
    );
    if (!mobileUnit) {
      continue;
    }

    unitMapObj.push({
      type: "unit",
      key: "model",
      id: unitId,
      value: "Unit_Hoodie_02", // yellow hoodie
    });
  }

  for (let i = 0; i < teamBLength; i++) {
    const unitId = getTeamUnitAtIndex(zone, TEAM_B, i);
    const mobileUnit = state.world?.mobileUnits?.find(
      (unit) => unit.id === unitId
    );
    if (!mobileUnit) {
      continue;
    }

    unitMapObj.push({
      type: "unit",
      key: "model",
      id: unitId,
      value: "Unit_Hoodie_05", // red hoodie
    });
  }

  mapObj.push(
    getCounterMapObj(
      state,
      block,
      gameState,
      "TW TeamA Counter",
      teamAScore,
      LEFT_COUNTER_MSG
    )
  );

  mapObj.push(
    getCounterMapObj(
      state,
      block,
      gameState,
      "TW TeamB Counter",
      teamBScore,
      RIGHT_COUNTER_MSG
    )
  );

  mapObj.push(
    getCountdownMapObj(
      state,
      block,
      "TW Countdown",
      teamALength,
      teamBLength,
      remainingTimeMs,
      gameState
    )
  );

  // Change appearance of bases if there is a match waiting on them
  // mapObj.push(
  //   ...getBuildingsByKind(state.world.buildings, "TW Lite Base")
  //     .filter((b) => {
  //       const matchID = getData(b, getTileMatchKey(b.location.tile.id));

  //       return matchID && matchID !== nullBytes32;
  //     })
  //     .map((b) => {
  //       return {
  //         type: "building",
  //         id: b.id,
  //         key: "model",
  //         value: "1-1-1", // top-bottom-color. This puts a gun on top and paints it pink
  //       };
  //     })
  // );

  return {
    version: 1,
    map: mapObj
      .concat(
        teamATiles.map((t) => ({
          type: "tile",
          id: t,
          key: "color",
          value: "#FEC953",
        }))
      )
      .concat(
        teamBTiles.map((t) => ({
          type: "tile",
          id: t,
          key: "color",
          value: "#F20D7B",
        }))
      )
      .concat(unitMapObj),
    components: [
      {
        id: "dbhq",
        type: "building",
        content: [
          {
            id: "default",
            type: "inline",
            html: "",
            buttons: [],
          },
        ],
      },
    ],
  };
}

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

function getCounterMapObj(
  state,
  block,
  gameState,
  counterBuildingName,
  count,
  msg
) {
  const counterBuilding = state.world?.buildings.find(
    (b) => b.kind?.name?.value == counterBuildingName
  );

  if (!msg) msg = 0;

  if (counterBuilding) {
    return {
      type: "building",
      id: `${counterBuilding.id}`,
      key: "labelText",
      value:
        gameState == GAME_STATE_NOT_STARTED
          ? msg.slice(block % msg.length, (block % msg.length) + 1)
          : `${count}`,
    };
  } else {
    return {};
  }
}

function getCountdownMapObj(
  state,
  block,
  counterBuildingName,
  teamALength,
  teamBLength,
  remainingTimeMs,
  gameState
) {
  const maxDisplayChars = 4;
  const counterBuilding = state.world?.buildings.find(
    (b) => b.kind?.name?.value == counterBuildingName
  );

  const getMessage = () => {
    let msg =
      teamALength > 0 || teamBLength > 0
        ? `${teamALength}V${teamBLength}`
        : CLOCK_MSG;

    if (msg.length > maxDisplayChars) {
      // scroll it
      const startSlice = block % msg.length;
      return (msg + msg).slice(startSlice, startSlice + maxDisplayChars);
    } else {
      // display it
      return msg;
    }
  };

  if (counterBuilding) {
    return {
      type: "building",
      id: `${counterBuilding.id}`,
      key: "labelText",
      value:
        gameState == GAME_STATE_NOT_STARTED
          ? getMessage()
          : formatTime(remainingTimeMs),
    };
  } else {
    return {};
  }
}

function getTeamUnitAtIndex(zone, team, index) {
  return getDataBytes24(zone, `${team}Unit_${index}`);
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

// --- Helper functions

const getBuildingsByKind = (buildingsArray, kind) => {
  return buildingsArray.filter(
    (building) =>
      building.kind?.name?.value.toLowerCase().trim() ==
      kind.toLowerCase().trim()
  );
};

function getMobileUnitFeeSlot(state) {
  const mobileUnit = getMobileUnit(state);
  const mobileUnitBags = mobileUnit ? getEquipeeBags(state, mobileUnit) : [];
  const { bag, slotKey } = findBagAndSlot(
    mobileUnitBags,
    prizeItemId,
    prizeFee
  );
  const unitFeeBagSlot = bag ? bag.equipee.key : -1;
  const unitFeeItemSlot = bag ? slotKey : -1;
  return {
    unitFeeBagSlot,
    unitFeeItemSlot,
  };
}

function getMobileUnit(state) {
  return state?.selected?.mobileUnit;
}

// search through all the bags in the world to find those belonging to this eqipee
// eqipee maybe a building, a mobileUnit or a tile
function getEquipeeBags(state, equipee) {
  return equipee
    ? (state?.world?.bags || []).filter(
        (bag) => bag.equipee?.node.id === equipee.id
      )
    : [];
}

// get first slot in bags that matches item requirements
function findBagAndSlot(bags, requiredItemId, requiredBalance) {
  for (const bag of bags) {
    for (const slotKey in bag.slots) {
      const slot = bag.slots[slotKey];
      if (
        (!requiredItemId || slot.item.id == requiredItemId) &&
        requiredBalance <= slot.balance
      ) {
        return {
          bag: bag,
          slotKey: slot.key, // assuming each slot has a 'key' property
        };
      }
    }
  }
  return { bag: null, slotKey: -1 };
}

// -- Zone Data

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
