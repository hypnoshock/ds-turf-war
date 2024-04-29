import ds from "downstream";

const nullBytes24 = `0x${"00".repeat(24)}`;
const TILE_ID_PREFIX = "0xe5a62ffc";

//COUNTING TILES
const p1TileList = [];
const p2TileList = [];

let teamBCounter;
let teamACounter;

export default async function update(state, block) {
  const zone = state.world;
  // const implementationAddr = zone.kind.implementation.id.slice(-40);
  // console.log("Judge implementationAddr", implementationAddr);

  const mapObj = [];

  const {
    prizePool,
    gameState,
    startBlock,
    endBlock,
    teamALength,
    teamBLength,
    teamATiles,
    teamBTiles,
    teamAPlayers,
    teamBPlayers,
  } = getTurfWarsState(state, zone);

  // console.log("teamATiles", teamATiles);
  // console.log("teamAPlayers", teamAPlayers);

  const teamAScore = teamATiles.length;
  const teamBScore = teamBTiles.length;

  // unit plugin properties - unit color
  const unitMapObj = [];
  for (let i = 0; i < teamALength; i++) {
    const unitId = getTeamUnitAtIndex(zone, "TeamA", i);
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
    const unitId = getTeamUnitAtIndex(zone, "TeamB", i);
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

  mapObj.push(getCounterMapObj(state, "TeamACounterDisplay", teamAScore));
  mapObj.push(getCounterMapObj(state, "TeamBCounterDisplay", teamBScore));

  // check current game state:
  // - NotStarted : GameActive == false
  // - Running : GameActive == true && endBlock < currentBlock
  // - GameOver : GameActive == true && endBlock >= currentBlock

  const nowBlock = block;
  const blocksLeft = endBlock > nowBlock ? endBlock - nowBlock : 0;
  const blocksFromStart = nowBlock - startBlock;
  const timeLeftMs = blocksLeft * 2 * 1000;
  const timeSinceStartMs =
    startBlock <= nowBlock ? blocksFromStart * 2 * 1000 : countdownTotalTime;

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

// ------------------------------------------------------- Turf Wars helpers

function getTurfWarsState(state, zone) {
  if (!zone) {
    throw new Error("Zone not found");
  }
  const prizePool = getDataInt(zone, "prizePool");
  const gameState = getDataInt(zone, "gameState");
  const startBlock = getDataInt(zone, "startBlock");
  const endBlock = getDataInt(zone, "endBlock");
  const teamALength = getDataInt(zone, "teamALength");
  const teamBLength = getDataInt(zone, "teamBLength");

  const teamAPlayers = [];
  for (let i = 0; i < teamALength; i++) {
    const unitId = getTeamUnitAtIndex(zone, "teamA", i);
    const mobileUnit = state.world?.mobileUnits?.find(
      (unit) => unit.id === unitId
    );
    if (mobileUnit) {
      teamAPlayers.push(mobileUnit.owner.id);
    } else {
      console.warn("Mobile unit not found for team A player", unitId);
    }
  }

  const teamBPlayers = [];
  for (let i = 0; i < teamBLength; i++) {
    const unitId = getTeamUnitAtIndex(zone, "teamB", i);
    const mobileUnit = state.world?.mobileUnits?.find(
      (unit) => unit.id === unitId
    );
    if (mobileUnit) {
      teamBPlayers.push(mobileUnit.owner.id);
    } else {
      console.warn("Mobile unit not found for team B player", unitId);
    }
  }

  const teamATiles = [];
  const teamBTiles = [];
  zone.allData.forEach((data) => {
    if (data.name.includes("_winner")) {
      const tileId = data.name.split("_")[0];
      if (
        !!teamAPlayers.some(
          (playerAddr) =>
            playerAddr.toLowerCase() == data.value.slice(0, 50).toLowerCase()
        )
      ) {
        teamATiles.push(tileId);
      } else if (
        !!teamBPlayers.some(
          (playerAddr) =>
            playerAddr.toLowerCase() == data.value.slice(0, 50).toLowerCase()
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
  };
}

function getCounterMapObj(state, counterBuildingName, count) {
  const counterBuilding = state.world?.buildings.find(
    (b) => b.kind?.name?.value == counterBuildingName
  );

  if (counterBuilding) {
    return {
      type: "building",
      id: `${counterBuilding.id}`,
      key: "labelText",
      value: `${count}`,
    };
  } else {
    return {};
  }
}

// ---------------------------------- //

const getBuildingsByType = (buildingsArray, type) => {
  return buildingsArray.filter(
    (building) =>
      building.kind?.name?.value.toLowerCase().trim() ==
      type.toLowerCase().trim()
  );
};

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

// --- Generic State helper functions

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

function logState(state) {
  console.log("State sent to pluging:", state);
}

// get an array of buildings withiin 5 tiles of building
function range5(state, building) {
  const range = 5;
  const tileCoords = getTileCoords(building?.location?.tile?.coords);
  let i = 0;
  const foundBuildings = [];
  for (let q = tileCoords[0] - range; q <= tileCoords[0] + range; q++) {
    for (let r = tileCoords[1] - range; r <= tileCoords[1] + range; r++) {
      let s = -q - r;
      let nextTile = [q, r, s];
      if (distance(tileCoords, nextTile) <= range) {
        state?.world?.buildings.forEach((b) => {
          if (!b?.location?.tile?.coords) return;

          const buildingCoords = getTileCoords(b.location.tile.coords);
          if (
            buildingCoords[0] == nextTile[0] &&
            buildingCoords[1] == nextTile[1] &&
            buildingCoords[2] == nextTile[2]
          ) {
            foundBuildings[i] = b;
            i++;
          }
        });
      }
    }
  }
  return foundBuildings;
}

function hexToSignedDecimal(hex) {
  if (hex.startsWith("0x")) {
    hex = hex.substr(2);
  }

  let num = parseInt(hex, 16);
  let bits = hex.length * 4;
  let maxVal = Math.pow(2, bits);

  // Check if the highest bit is set (negative number)
  if (num >= maxVal / 2) {
    num -= maxVal;
  }

  return num;
}

// Get tile coordinates from hexadecimal coordinates
function getTileCoords(coords) {
  return [
    hexToSignedDecimal(coords[0]),
    hexToSignedDecimal(coords[1]),
    hexToSignedDecimal(coords[2]),
    hexToSignedDecimal(coords[3]),
  ];
}

function distance(tileCoords, nextTile) {
  return Math.max(
    Math.abs(tileCoords[0] - nextTile[0]),
    Math.abs(tileCoords[1] - nextTile[1]),
    Math.abs(tileCoords[2] - nextTile[2])
  );
}

function getBuildingKindsByTileLocation(state, building, kindID) {
  return (state?.world?.buildings || []).find(
    (b) => b.id === building.id && b.kind?.name?.value == kindID
  );
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

function getTileIdFromCoords(coords) {
  const z = toInt16Hex(coords[0]);
  const q = toInt16Hex(coords[1]);
  const r = toInt16Hex(coords[2]);
  const s = toInt16Hex(coords[3]);
  return `${TILE_ID_PREFIX}000000000000000000000000${z}${q}${r}${s}`;
}

// Convert an integer to a 16-bit hexadecimal string
function toInt16Hex(value) {
  return ("0000" + toTwos(value, 16).toString(16)).slice(-4);
}

const BN_0 = BigInt(0);
const BN_1 = BigInt(1);

// Convert a two's complement binary representation to a BigInt
function fromTwos(n, w) {
  let value = BigInt(n);
  let width = BigInt(w);
  if (value >> (width - BN_1)) {
    const mask = (BN_1 << width) - BN_1;
    return -((~value & mask) + BN_1);
  }
  return value;
}

// Convert a BigInt to a two's complement binary representation
function toTwos(_value, _width) {
  let value = BigInt(_value);
  let width = BigInt(_width);
  const limit = BN_1 << (width - BN_1);
  if (value < BN_0) {
    value = -value;
    const mask = (BN_1 << width) - BN_1;
    return (~value & mask) + BN_1;
  }
  return value;
}
