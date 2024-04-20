import ds from "downstream";

const prizeFee = 2;
const prizeItemId = "0x6a7a67f08c72b94400000001000000010000000000000000"; // green goo
const buildingPrizeBagSlot = 0;
const buildingPrizeItemSlot = 0;
const nullBytes24 = `0x${"00".repeat(24)}`;
const burgerCounterKindId = "Burger Display Building";
const duckCounterKindId = "Duck Display Building";
const TILE_ID_PREFIX = "0xe5a62ffc";

//COUNTING TILES
const p1TileList = [];
const p2TileList = [];

let burgerCounter;
let duckCounter;

export default async function update(state, block) {
  // console.log(state)
  //
  // Action handler functions
  //

  // An action can set a form submit handler which will be called after the action along with the form values
  let handleFormSubmit;

  //ASSIGN TEAMS
  const join = () => {
    if (unitFeeBagSlot < 0) {
      console.log("fee not found in bags - button should have been disabled");
    }
    const mobileUnit = getMobileUnit(state);

    const payload = ds.encodeCall("function join()", []);

    const dummyBagIdIncaseToBagDoesNotExist = `0x${"00".repeat(24)}`;

    ds.dispatch(
      {
        name: "TRANSFER_ITEM_MOBILE_UNIT",
        args: [
          mobileUnit.id,
          [mobileUnit.id, selectedBuilding.id],
          [unitFeeBagSlot, buildingPrizeBagSlot],
          [unitFeeItemSlot, buildingPrizeItemSlot],
          dummyBagIdIncaseToBagDoesNotExist,
          prizeFee,
        ],
      },
      {
        name: "BUILDING_USE",
        args: [selectedBuilding.id, mobileUnit.id, payload],
      }
    );
  };

  // NOTE: Because the 'action' doesn't get passed the form values we are setting a global value to a function that will
  const start = () => {
    // /todo - offer a way of choosing which buildingkinds
    // are eligible for each team

    const selectedBuildingIdDuck =
      "0xbe92755c0000000000000000546391e80000000000000003";
    const selectedBuildingIdBurger =
      "0xbe92755c0000000000000000444749c70000000000000003";

    const mobileUnit = getMobileUnit(state);
    const payload = ds.encodeCall(
      "function start(bytes24 duckBuildingID, bytes24 burgerBuildingID)",
      [selectedBuildingIdDuck, selectedBuildingIdBurger]
    );

    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, mobileUnit.id, payload],
    });
  };

  const claim = () => {
    const mobileUnit = getMobileUnit(state);

    const payload = ds.encodeCall("function claim()", []);

    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, mobileUnit.id, payload],
    });
  };

  const reset = () => {
    const mobileUnit = getMobileUnit(state);
    const payload = ds.encodeCall("function reset()", []);

    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, mobileUnit.id, payload],
    });
  };

  const dvbBuildingName = "Judge";
  const selectedBuilding = state.world?.buildings.find(
    (b) => b.kind?.name?.value == dvbBuildingName
  );

  // early out if we don't have any buildings or state isn't ready
  if (!selectedBuilding || !state?.world?.buildings) {
    // console.log("NO DVB BUILDING FOUND");
    return {
      version: 1,
      map: [],
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

  /////////////////////////////// UPDATE LOOP ///////////////////////////////

  // Easier way of getting the implementation address during deploy?
  const implementationAddr = selectedBuilding.kind.implementation.id.slice(-40);
  console.log("Judge implementationAddr", implementationAddr);

  const {
    prizePool,
    gameActive,
    startBlock,
    endBlock,
    teamDuckLength,
    teamBurgerLength,
    teamATiles,
    teamBTiles,
  } = getTurfWarsState(selectedBuilding);

  const { unitFeeBagSlot, unitFeeItemSlot } = getMobileUnitFeeSlot(state);
  const hasFee = unitFeeBagSlot >= 0;
  const localBuildings = range5(state, selectedBuilding);
  const duckCount = teamATiles.length;
  const burgerCount = teamBTiles.length;

  connectDisplayBuildings(state, localBuildings);

  // unit plugin properties - unit color
  const unitMapObj = [];
  // const hqCoords = selectedBuilding.location?.tile?.coords;
  for (let i = 0; i < teamDuckLength; i++) {
    const unitId = getHQTeamUnit(selectedBuilding, "Duck", i);
    const mobileUnit = state.world?.mobileUnits?.find(
      (unit) => unit.id === unitId
    );
    if (!mobileUnit) {
      console.log("no unit");
      continue;
    }
    // const unitCoords = mobileUnit.nextLocation?.tile?.coords;

    const unitTileCoords = getTileCoords(
      mobileUnit?.nextLocation?.tile?.coords
    );
    const tId = getTileIdFromCoords(unitTileCoords);

    unitMapObj.push({
      type: "unit",
      key: "model",
      id: unitId,
      value: "Unit_Hoodie_02", // yellow hoodie
    });

    if (!p1TileList.includes(tId) && !p2TileList.includes(tId)) {
      p1TileList.push(tId);

      unitMapObj.push({
        type: "tile",
        key: "color",
        id: getTileIdFromCoords(unitTileCoords),
        value: "#FEC953",
      });
    }
  }
  for (let i = 0; i < teamBurgerLength; i++) {
    const unitId = getHQTeamUnit(selectedBuilding, "Burger", i);
    const mobileUnit = state.world?.mobileUnits?.find(
      (unit) => unit.id === unitId
    );
    if (!mobileUnit) {
      continue;
    }
    // const unitCoords = mobileUnit.nextLocation?.tile?.coords;

    const unitTileCoords = getTileCoords(
      mobileUnit?.nextLocation?.tile?.coords
    );
    const tId = getTileIdFromCoords(unitTileCoords);

    unitMapObj.push({
      type: "unit",
      key: "model",
      id: unitId,
      value: "Unit_Hoodie_05", // red hoodie
    });

    if (!p1TileList.includes(tId) && !p2TileList.includes(tId)) {
      p2TileList.push(tId);

      unitMapObj.push({
        type: "tile",
        key: "color",
        id: getTileIdFromCoords(unitTileCoords),
        value: "#F20D7B",
      });
    }
  }

  const counterOneBuilding = state.world?.buildings.find(
    (b) => b.kind?.name?.value == "Counter1New"
  );

  const counterTwoBuilding = state.world?.buildings.find(
    (b) => b.kind?.name?.value == "Counter2New"
  );

  if (counterOneBuilding) {
    unitMapObj.push({
      type: "building",
      id: `${counterOneBuilding.id}`,
      key: "labelText",
      value: `${teamATiles.length}`,
    });
  }

  if (counterTwoBuilding) {
    unitMapObj.push({
      type: "building",
      id: `${counterTwoBuilding.id}`,
      key: "labelText",
      value: `${teamBTiles.length}`,
    });
  }

  // check current game state:
  // - NotStarted : GameActive == false
  // - Running : GameActive == true && endBlock < currentBlock
  // - GameOver : GameActive == true && endBlock >= currentBlock

  // we build a list of button objects that are rendered in the building UI panel when selected
  let buttonList = [];

  // we build an html block which is rendered above the buttons
  let htmlBlock = "<h3>Ducks vs Burgers HQ</h3>";
  htmlBlock += `<p>payout for win: ${prizeFee * 2}</p>`;
  htmlBlock += `<p>payout for draw: ${prizeFee}</p></br>`;

  const canJoin = !gameActive && hasFee;
  const canStart = !gameActive && teamDuckLength > 0 && teamBurgerLength > 0;

  if (canJoin) {
    htmlBlock += `<p>total players: ${
      teamDuckLength + teamBurgerLength
    }</p></br>`;
  }

  // Show what team the unit is on
  const mobileUnit = getMobileUnit(state);
  let isOnTeam = false;
  if (mobileUnit) {
    let unitTeam = "";

    for (let i = 0; i < teamDuckLength; i++) {
      if (mobileUnit.id == getHQTeamUnit(selectedBuilding, "Duck", i)) {
        unitTeam = "🐤";
        break;
      }
    }

    if (unitTeam === "") {
      for (let i = 0; i < teamBurgerLength; i++) {
        if (mobileUnit.id == getHQTeamUnit(selectedBuilding, "Burger", i)) {
          unitTeam = "🍔";
          break;
        }
      }
    }

    if (unitTeam !== "") {
      isOnTeam = true;
      htmlBlock += `
                <p>You are on team ${unitTeam}</p></br>
            `;
    }

    const judgeBuilding = state.world?.buildings.find(
      (b) => b.kind?.name?.value == "Judge"
    );

    /////////////////////////////////////////////////////////////////////////////////////// PAINT TILES

    const buildingTileCoords = getTileCoords(
      judgeBuilding?.location?.tile?.coords
    );
    const unitTileCoords = getTileCoords(
      mobileUnit?.nextLocation?.tile?.coords
    );
    const unitDistanceFromBuilding = distance(
      buildingTileCoords,
      unitTileCoords
    );

    const tId = getTileIdFromCoords(unitTileCoords);

    const mobileUnits = state.world?.mobileUnits;

    mobileUnits.forEach((unit) => {
      if (unit.id == getHQTeamUnit(selectedBuilding, "Duck", 0)) {
        // Orange tile under the unit
        if (!p1TileList.includes(tId) && !p2TileList.includes(tId)) {
          p1TileList.push(tId);
          console.log(p1TileList.length);

          unitMapObj.push({
            type: "tile",
            key: "color",
            id: getTileIdFromCoords(unitTileCoords),
            value: "#FEC953",
          });
        }
      }

      if (unit.id == getHQTeamUnit(selectedBuilding, "Burger", 0)) {
        // Orange tile under the unit
        if (!p1TileList.includes(tId) && !p2TileList.includes(tId)) {
          p2TileList.push(tId);
          console.log(p2TileList.length);

          unitMapObj.push({
            type: "tile",
            key: "color",
            id: getTileIdFromCoords(unitTileCoords),
            value: "#F20D7B",
          });
        }
      }
    });
  }

  if (!gameActive) {
    if (!isOnTeam) {
      buttonList.push({
        text: `Join Game (${prizeFee} Green Goo)`,
        type: "action",
        action: join,
        disabled: !canJoin || isOnTeam,
      });
    } else {
      // Check reason why game can't start
      const waitingForStartCondition =
        teamDuckLength != teamBurgerLength ||
        teamDuckLength + teamBurgerLength < 2;
      let startConditionMessage = "";
      if (waitingForStartCondition) {
        if (teamDuckLength + teamBurgerLength < 2) {
          startConditionMessage = "Waiting for players...";
        } else if (teamDuckLength != teamBurgerLength) {
          startConditionMessage = "Teams must be balanced...";
        }
      }

      buttonList.push({
        text: waitingForStartCondition ? startConditionMessage : "Start",
        type: "action",
        action: start,
        disabled: !canStart || teamDuckLength != teamBurgerLength,
      });
    }
  }

  const nowBlock = block;
  const blocksLeft = endBlock > nowBlock ? endBlock - nowBlock : 0;
  const blocksFromStart = nowBlock - startBlock;
  const timeLeftMs = blocksLeft * 2 * 1000;
  const timeSinceStartMs =
    startBlock <= nowBlock ? blocksFromStart * 2 * 1000 : countdownTotalTime;

  if (gameActive) {
    // Display selected team buildings
    htmlBlock += `
            <h3>Team Buildings:</h3>
            <p>Team 🐤: Weak Duck</p>
            <p>Team 🍔: Weak Burger</p></br>

        `;

    const now = Date.now();

    if (blocksLeft > 0) {
      htmlBlock += `<p>time remaining: ${formatTime(timeLeftMs)}</p>`;
    } else {
      // End of game
      buttonList.push({
        text: prizePool > 0 ? `Claim Reward` : "Nothing to Claim",
        type: "action",
        action: claim,
        disabled: prizePool == 0,
      });

      htmlBlock += `
                <h3 style="margin-top: 1em;">Game Over:</h3>
                <p>Final Score: 🐤${duckCount} : 🍔${burgerCount}
            `;
      if (duckCount == burgerCount) {
        htmlBlock += `
                    <p>The result was a draw</p>
                `;
      } else {
        const winningTeamName = duckCount > burgerCount ? "duck" : "burger";
        const winningTeamEmoji = duckCount > burgerCount ? "🐤" : "🍔";
        htmlBlock += `
                    <p>Team <b>${winningTeamName}</b> have won the match!</p>
                    <p style="text-align: center;">${winningTeamEmoji}🏆</p>
                `;
      }
    }
  }

  // Reset is always offered (requires some trust!)
  buttonList.push({
    text: "Reset",
    type: "action",
    action: reset,
    disabled: false,
  });

  // build up an array o fmap objects which are used to update display buildings
  // always show the current team counts
  const mapObj = [
    {
      type: "building",
      id: `${burgerCounter ? burgerCounter.id : ""}`,
      key: "labelText",
      value: `${burgerCount}`,
    },
    {
      type: "building",
      id: `${duckCounter ? duckCounter.id : ""}`,
      key: "labelText",
      value: `${duckCount}`,
    },
  ];

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
            html: htmlBlock,
            buttons: buttonList,
          },
        ],
      },
    ],
  };
}

// --- Duckbur HQ Specific functions

function getTurfWarsState(selectedBuilding) {
  const prizePool = getDataInt(selectedBuilding, "prizePool");
  const gameActive = getDataBool(selectedBuilding, "gameActive");
  const startBlock = getDataInt(selectedBuilding, "startBlock");
  const endBlock = getDataInt(selectedBuilding, "endBlock");
  const buildingKindIdDuck = getDataBytes24(
    selectedBuilding,
    "buildingKindIdDuck"
  );
  const buildingKindIdBurger = getDataBytes24(
    selectedBuilding,
    "buildingKindIdBurger"
  );
  const teamDuckLength = getDataInt(selectedBuilding, "teamDuckLength");
  const teamBurgerLength = getDataInt(selectedBuilding, "teamBurgerLength");

  const teamATiles = [];
  const teamBTiles = [];
  selectedBuilding.allData.forEach((data) => {
    if (data.name.includes("_winner")) {
      const tileId = data.name.split("_")[0];

      if (
        data.value ==
        "0x045820b3f39Fd6e51aad88F6F4ce6aB8827279cffFb922660000000000000000"
      ) {
        teamATiles.push(tileId);
      } else if (
        data.value ==
        "0x045820b323618e81e3f5cdf7f54c3d65f7fbc0abf5b21e8f0000000000000000"
      ) {
        teamBTiles.push(tileId);
      }
    }
  });

  return {
    prizePool,
    gameActive,
    startBlock,
    endBlock,
    startBlock,
    buildingKindIdDuck,
    buildingKindIdBurger,
    teamDuckLength,
    teamBurgerLength,
    teamATiles,
    teamBTiles,
  };
}

// ---------------------------------- //

const getBuildingsByType = (buildingsArray, type) => {
  return buildingsArray.filter(
    (building) =>
      building.kind?.name?.value.toLowerCase().trim() ==
      type.toLowerCase().trim()
  );
};

function getHQTeamUnit(selectedBuilding, team, index) {
  return getDataBytes24(selectedBuilding, `team${team}Unit_${index}`);
}

// search the buildings list ofr the display buildings we're gpoing to use
// for team counts and coutdown
function connectDisplayBuildings(state, buildings) {
  if (!burgerCounter) {
    burgerCounter = buildings.find((element) =>
      getBuildingKindsByTileLocation(state, element, burgerCounterKindId)
    );
  }
  if (!duckCounter) {
    duckCounter = buildings.find((element) =>
      getBuildingKindsByTileLocation(state, element, duckCounterKindId)
    );
  }
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

const countBuildings = (buildingsArray, kindID, startBlock, endBlock) => {
  return buildingsArray.filter(
    (b) =>
      b.kind?.id == kindID &&
      b.constructionBlockNum.value >= startBlock &&
      b.constructionBlockNum.value <= endBlock
  ).length;
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

// function PaintAllTiles(list)
// {
//     for (let t = 0; t < list.length; t++) {
//         const element = list[t];
//         unitMapObj.push({
//             type: 'tile',
//             key: 'color',
//             id: getTileIdFromCoords(unitTileCoords),
//             value: '#FEC953',
//         });
//     }

// }

// the source for this code is on github where you can find other example buildings:
// https://github.com/playmint/ds/tree/main/contracts/src/example-plugins
