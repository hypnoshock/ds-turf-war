import ds from "downstream";

const nullBytes24 = `0x${"00".repeat(24)}`;

const TEAM_A = "team1";
const TEAM_B = "team2";

const BLOCK_TIME_SECS = 2;
const GAME_STATE_NOT_STARTED = 0;
const GAME_STATE_IN_PROGRESS = 1;
const GAME_STATE_FINISHED = 2;
const START_HAMMER_QTY = 2;

const DATA_HAS_CLAIMED_PRIZES = "hasClaimedPrizes";

export default async function update(state, block) {
  const buildings = state.world?.buildings || [];
  const mobileUnit = getMobileUnit(state);
  const selectedTile = getSelectedTile(state);
  const selectedBuilding =
    selectedTile && getBuildingOnTile(state, selectedTile);

  // Early out if no mobile unit
  if (!mobileUnit || !selectedBuilding) {
    return {
      version: 1,
      components: [
        {
          id: "turf-wars-hq",
          type: "building",
          content: [
            {
              id: "default",
              type: "inline",
              html: `<p>Select your mobile unit to join a team</p>`,
            },
          ],
        },
      ],
    };
  }

  const {
    teamAPlayers,
    teamBPlayers,
    teamATiles,
    teamBTiles,
    dirtyTiles,
    gameState,
  } = getTurfWarsState(state, block, state.world);

  const isPlayerTeamA = teamAPlayers.some(
    (unitId) => mobileUnit?.id.toLowerCase() == unitId.toLowerCase()
  );
  const isPlayerTeamB = teamBPlayers.some(
    (unitId) => mobileUnit?.id.toLowerCase() == unitId.toLowerCase()
  );

  const joinTeam = () => {
    if (!mobileUnit) {
      console.log("no selected unit");
      return;
    }

    let startLocation = [];
    if (teamAPlayers.length <= teamBPlayers.length) {
      // Team A
      console.log("Joining Team A");
      startLocation = [0, -5, 5];
    } else {
      // Team B
      console.log("Joining Team B");
      startLocation = [0, 5, -5];
    }
    const [toEquipSlot, toItemSlot] = getCompatibleOrEmptySlot(
      mobileUnit,
      "TW Hammer",
      START_HAMMER_QTY
    );
    ds.dispatch(
      {
        name: "ZONE_USE",
        args: [
          mobileUnit.id,
          ds.encodeCall("function join(bytes24)", [
            selectedBuilding.location.tile.id,
          ]),
        ],
      },
      {
        name: "TRANSFER_ITEM_MOBILE_UNIT",
        args: [
          mobileUnit.id,
          [selectedBuilding.location.tile.id, mobileUnit.id],
          [0, toEquipSlot],
          [0, toItemSlot],
          nullBytes24,
          START_HAMMER_QTY,
        ],
      },
      {
        name: "MOVE_MOBILE_UNIT",
        args: [mobileUnit.nextLocation.tile.coords[0], ...startLocation],
      },
      {
        name: "ZONE_USE",
        args: [
          mobileUnit.id,
          ds.encodeCall("function destroyTileBag(bytes24,bytes24,bytes24[])", [
            selectedBuilding.location.tile.id,
            generateDevBagId(selectedBuilding.location.tile),
            [nullBytes24, nullBytes24, nullBytes24, nullBytes24], // The dev destroy bag action is mental - it uses the length of the array to determine slot count. Doesn't care about contents!
          ]),
        ],
      }
    );
  };

  const moveToStartTile = () => {
    if (!mobileUnit) {
      console.log("no selected unit");
      return;
    }

    if (isPlayerTeamA) {
      ds.dispatch({
        name: "MOVE_MOBILE_UNIT",
        args: [mobileUnit.nextLocation.tile.coords[0], 0, -5, 5],
      });
    } else {
      ds.dispatch({
        name: "MOVE_MOBILE_UNIT",
        args: [mobileUnit.nextLocation.tile.coords[0], 0, 5, -5],
      });
    }
  };

  const claimPrizes = () => {
    if (!mobileUnit) {
      console.log("no selected unit");
      return;
    }

    const baseBuildingIds = getBuildingsByType(buildings, "TW Lite Base").map(
      (b) => b.id
    );

    ds.dispatch(
      {
        name: "BUILDING_USE",
        args: [
          selectedBuilding.id,
          mobileUnit.id,
          ds.encodeCall("function claimPrizes()", []),
        ],
      },
      {
        name: "ZONE_USE",
        args: [
          mobileUnit.id,
          ds.encodeCall("function reset(bytes24[], bytes24[])", [
            dirtyTiles,
            baseBuildingIds,
          ]),
        ],
      }
    );
  };

  const resetGame = () => {
    console.log("Resetting game");

    const baseBuildingIds = getBuildingsByType(buildings, "TW Lite Base").map(
      (b) => b.id
    );

    ds.dispatch({
      name: "ZONE_USE",
      args: [
        mobileUnit.id,
        ds.encodeCall("function reset(bytes24[], bytes24[])", [
          dirtyTiles,
          baseBuildingIds,
        ]),
      ],
    });
  };

  const buttons = [];
  let html = "";
  switch (gameState) {
    case GAME_STATE_NOT_STARTED: {
      if (!isPlayerTeamA && !isPlayerTeamB) {
        buttons.push({
          text: "Join Team",
          type: "action",
          action: joinTeam,
          disabled: !!!mobileUnit,
        });
      } else {
        html = `<h2>Game Not Started</h2><p>You are on ${isPlayerTeamA ? "🟡Yellow" : "🔴Red"} Team</p>`;
        buttons.push({
          text: "Move to Start Tile",
          type: "action",
          action: moveToStartTile,
          disabled: !!!mobileUnit,
        });
      }
      break;
    }
    case GAME_STATE_IN_PROGRESS: {
      html = `<h2>Game in Progress</h2><h3>Score</h3><p>🟡Yellow Team: ${teamATiles.length}</p><p>🔴Red Team: ${teamBTiles.length}</p>`;
      if (isPlayerTeamA || isPlayerTeamB) {
        buttons.push({
          text: "Reset Game",
          type: "action",
          action: resetGame,
          disabled: !!!mobileUnit,
        });
      }
      break;
    }
    case GAME_STATE_FINISHED: {
      html = `<h2>Game Over</h2><p><h3>Score</h3><p>🟡Yellow Team: ${teamATiles.length}</p><p>🔴Red Team: ${teamBTiles.length}</p><h2>${getWinText(teamATiles.length, teamBTiles.length)}</h2>${teamATiles.length != teamBTiles.length ? "<p>Prizes will be distributed to the winning team</p>" : ""}`;
      buttons.push({
        text: "Reset Game",
        type: "action",
        action: claimPrizes,
        disabled: getDataBool(state.world, DATA_HAS_CLAIMED_PRIZES),
      });
      break;
    }
  }

  return {
    version: 1,
    components: [
      {
        id: "turf-wars-hq",
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

function getWinText(teamAScore, teamBScore) {
  if (teamAScore === teamBScore) {
    return "It's a draw!";
  }
  return teamAScore > teamBScore ? "Yellow Wins!" : "Red Wins!";
}

// copied from Zone.js
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

// ---- Turf Wars Helper Functions ----

function getTeamUnitAtIndex(zone, team, index) {
  return getDataBytes24(zone, `${team}Unit_${index}`);
}

// ---- Helper functions ----

const getBuildingsByType = (buildingsArray, type) => {
  return buildingsArray.filter((building) =>
    building.kind?.name?.value.toLowerCase().includes(type.toLowerCase())
  );
};

function getMobileUnit(state) {
  return state?.selected?.mobileUnit;
}

function getBuildingOnTile(state, tile) {
  return (state?.world?.buildings || []).find(
    (b) => tile && b.location?.tile?.id === tile.id
  );
}

function getSelectedTile(state) {
  const tiles = state?.selected?.tiles || {};
  return tiles && tiles.length === 1 ? tiles[0] : undefined;
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

// ---- Data functions ----

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
