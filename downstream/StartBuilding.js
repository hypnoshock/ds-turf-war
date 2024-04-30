import ds from "downstream";

const STATE_NOT_STARTED = 0;
const STATE_IN_PROGRESS = 1;

export default async function update(state) {
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
              html: `<h3>Turf Wars HQ</h3><p>Select your mobile unit to interact with this building</p>`,
            },
          ],
        },
      ],
    };
  }

  const { teamAPlayers, teamBPlayers, gameState } = getTurfWarsState(
    state,
    state.world
  );
  const isPlayerTeamA = teamAPlayers.some(
    (playerNodeId) =>
      mobileUnit?.owner.id.toLowerCase() == playerNodeId.toLowerCase()
  );
  const isPlayerTeamB = teamBPlayers.some(
    (playerNodeId) =>
      mobileUnit?.owner.id.toLowerCase() == playerNodeId.toLowerCase()
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
    case STATE_NOT_STARTED: {
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
    case STATE_IN_PROGRESS: {
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

function getTurfWarsState(state, zone) {
  if (!zone) {
    throw new Error("Zone not found");
  }
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
