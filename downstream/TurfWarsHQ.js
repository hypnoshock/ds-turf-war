import ds from "downstream";

const STATE_NOT_STARTED = 0;
const STATE_IN_PROGRESS = 1;

export default async function update(state) {
  const buildings = state.world?.buildings || [];
  const mobileUnit = getMobileUnit(state);

  // Early out if no mobile unit
  if (!mobileUnit) {
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
        args: [mobileUnit.id, ds.encodeCall("function join()", [])],
      },
      {
        name: "MOVE_MOBILE_UNIT",
        args: [mobileUnit.nextLocation.tile.coords[0], ...startLocation],
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
            html: `<h2>Turf Wars HQ</h2>`,
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
