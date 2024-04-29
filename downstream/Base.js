import ds from "downstream";

const nullBytes24 = `0x${"00".repeat(24)}`;
const nullBytes32 = `0x${"00".repeat(32)}`;
const TEAM_A = "teamA";
const TEAM_B = "teamB";

export default async function update(state) {
  //   const buildings = state.world?.buildings || [];
  const mobileUnit = getMobileUnit(state);
  const selectedTile = getSelectedTile(state);
  const selectedBuilding =
    selectedTile && getBuildingOnTile(state, selectedTile);

  // DEBUG
  // const implementationAddr = selectedBuilding.kind.implementation.id.slice(-40);
  // console.log("implementationAddr", implementationAddr);
  // console.log("selectedBuilding", selectedBuilding);
  // const winner = getData(selectedBuilding, getTileWinnerKey(selectedBuilding));
  // console.log("matchID", matchID);
  // console.log("winner", winner);

  const { teamAPlayers, teamBPlayers } = getTurfWarsState(state, state.world);

  const tileWinnerKey = getTileWinnerKey(selectedBuilding.location.tile.id);
  const winnerPlayerId = getDataBytes24(state.world, tileWinnerKey);
  const playerTeam = getTeam(teamAPlayers, teamBPlayers, mobileUnit.owner.id);
  const tileTeam = getTeam(teamAPlayers, teamBPlayers, winnerPlayerId);
  const matchID = getData(
    selectedBuilding,
    getTileMatchKey(selectedBuilding.location.tile.id)
  );
  // const matchWinner = getData(selectedBuilding, tileWinnerKey);

  const startBattle = () => {
    const payload = ds.encodeCall("function startBattle()", []);
    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, mobileUnit.id, payload],
    });
  };

  const claimWin = () => {
    const payload = ds.encodeCall("function claimWin()", []);
    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, mobileUnit.id, payload],
    });
  };

  const joinBattle = () => {};

  let html = ``;
  const buttons = [];
  if (playerTeam != tileTeam) {
    if (!matchID || matchID === nullBytes32) {
      buttons.push({
        text: "Start Battle",
        type: "action",
        action: startBattle,
        disabled: false,
      });
    } else {
      buttons.push({
        text: "Claim Win",
        type: "action",
        action: claimWin,
        disabled: false,
      });
    }
  }

  if (matchID && matchID !== nullBytes32) {
    html = `<a href="http://localhost:1337/match?asPlayer=&useExternalWallet=&match=${matchID}" target="_blank">Join Match</a>`;
    // buttons.push({
    //   text: "Join Battle",
    //   type: "action",
    //   action: joinBattle,
    //   disabled: false,
    // });
  }

  return {
    version: 1,
    components: [
      {
        id: "tutorial-5",
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

function getTeam(teamAPlayers, teamBPlayers, playerId) {
  if (teamAPlayers.includes(playerId)) {
    return TEAM_A;
  } else if (teamBPlayers.includes(playerId)) {
    return TEAM_B;
  } else {
    return "";
  }
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

// -- Match Data

function getTileMatchKey(tileId) {
  return tileId + "_entityID";
}

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
