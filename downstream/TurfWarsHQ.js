import ds from "downstream";

const nullBytes24 = `0x${"00".repeat(24)}`;

const STATE_NOT_STARTED = 0;
const STATE_IN_PROGRESS = 1;

export default async function update(state) {
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

  const { teamAPlayers, teamBPlayers, teamATiles, teamBTiles, gameState } =
    getTurfWarsState(state, state.world);

  const isPlayerTeamA = teamAPlayers.some(
    (playerNodeId) =>
      mobileUnit?.owner.id.toLowerCase() == playerNodeId.toLowerCase()
  );
  const isPlayerTeamB = teamBPlayers.some(
    (playerNodeId) =>
      mobileUnit?.owner.id.toLowerCase() == playerNodeId.toLowerCase()
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
          [0, 0],
          [0, 0],
          nullBytes24,
          2,
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

  const resetGame = () => {
    console.log("Resetting game");

    const baseBuildingIds = getBuildingsByType(buildings, "TW Base").map(
      (b) => b.id
    );

    ds.dispatch({
      name: "ZONE_USE",
      args: [
        mobileUnit.id,
        ds.encodeCall("function reset(bytes24[], bytes24[])", [
          [...teamATiles, ...teamBTiles],
          baseBuildingIds,
        ]),
      ],
    });
  };

  const buttons = [];
  switch (gameState) {
    case STATE_NOT_STARTED: {
      if (!isPlayerTeamA && !isPlayerTeamB) {
        buttons.push({
          text: "Join Team",
          type: "action",
          action: joinTeam,
          disabled: !!!mobileUnit,
        });
      } else {
        buttons.push({
          text: "Move to Start Tile",
          type: "action",
          action: moveToStartTile,
          disabled: !!!mobileUnit,
        });
      }
      break;
    }
    case STATE_IN_PROGRESS: {
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
            html: ``,
            buttons,
          },
        ],
      },
    ],
  };
}

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
