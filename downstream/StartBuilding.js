import ds from "downstream";

const TEAM_A = "team1";
const TEAM_B = "team2";
const BLOCK_TIME_SECS = 2;
const GAME_STATE_NOT_STARTED = 0;
const GAME_STATE_IN_PROGRESS = 1;
const GAME_STATE_FINISHED = 2;

export default async function update(state, block) {
  const mobileUnit = getMobileUnit(state);

  // Early out if no mobile unit
  if (!mobileUnit) {
    return {
      version: 1,
      components: [
        {
          id: "turf-wars-start",
          type: "building",
          content: [
            {
              id: "default",
              type: "inline",
              html: `<p>Select your mobile unit to interact with this building</p>`,
            },
          ],
        },
      ],
    };
  }

  const { teamAPlayers, teamBPlayers, gameState } = getTurfWarsState(
    state,
    block,
    state.world
  );
  const isPlayerTeamA = teamAPlayers.some(
    (unitId) => mobileUnit?.id.toLowerCase() == unitId.toLowerCase()
  );
  const isPlayerTeamB = teamBPlayers.some(
    (unitId) => mobileUnit?.id.toLowerCase() == unitId.toLowerCase()
  );

  const readyTeam = getDataInt(state.world, "ready");

  const setReady = () => {
    ds.dispatch({
      name: "ZONE_USE",
      args: [mobileUnit.id, ds.encodeCall("function setReady()", [])],
    });
  };

  const unsetReady = () => {
    ds.dispatch({
      name: "ZONE_USE",
      args: [mobileUnit.id, ds.encodeCall("function unsetReady()", [])],
    });
  };

  let html = "";
  const buttons = [];

  switch (gameState) {
    case GAME_STATE_NOT_STARTED: {
      if (
        (isPlayerTeamA && readyTeam == 1) ||
        (isPlayerTeamB && readyTeam == 2)
      ) {
        html = `<p>Waiting for other team to ready up</p>`;
        buttons.push({
          text: "Not Ready",
          type: "action",
          action: unsetReady,
          disabled: false,
        });
      } else {
        html = `<p>Click ready when your team is ready</p>`;
        buttons.push({
          text: "Ready",
          type: "action",
          action: setReady,
          disabled: false,
        });
      }
      break;
    }
    case GAME_STATE_IN_PROGRESS: {
      html = `<p>Game in progress</p>`;
    }
  }

  return {
    version: 1,
    components: [
      {
        id: "turf-wars-start",
        type: "building",
        content: [
          {
            id: "default",
            type: "inline",
            html,

            buttons: buttons,
          },
        ],
      },
    ],
  };
}

// ---- turf wars helper functions ----

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

function getTeamUnitAtIndex(zone, team, index) {
  return getDataBytes24(zone, `${team}Unit_${index}`);
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
