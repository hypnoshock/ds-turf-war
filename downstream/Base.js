import ds from "downstream";

const nullBytes24 = `0x${"00".repeat(24)}`;
const nullBytes32 = `0x${"00".repeat(32)}`;
const BLOCK_TIME_SECS = 2;
const TEAM_A = "teamA";
const TEAM_B = "teamB";

const NETWORK_LOCAl = 0;
const NETWORK_GARNET = 1;
const NETWORK_REDSTONE = 2;

const SS_URL_LOCAL = "http://localhost:1337";
const SS_URL_GARNET = "https://aa.skystrife.xyz";
const SS_URL_REDSTONE = "https://play.skystrife.xyz/";

export default async function update(state, block) {
  //   const buildings = state.world?.buildings || [];
  const mobileUnit = getMobileUnit(state);
  const selectedTile = getSelectedTile(state);
  const selectedBuilding =
    selectedTile && getBuildingOnTile(state, selectedTile);
  const zone = state.world;

  // DEBUG
  // console.log(state);
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
    const bagID = generateDevBagId(selectedBuilding.location.tile);
    console.log("bagID", bagID);
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
          [0, 0],
          [0, 0],
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

  const getMatchURL = () => {
    const network = getDataInt(zone, "network");
    let skyStrifeUrl = SS_URL_LOCAL;
    switch (network) {
      case NETWORK_LOCAl:
        skyStrifeUrl = SS_URL_LOCAL;
        break;
      case NETWORK_GARNET:
        skyStrifeUrl = SS_URL_GARNET;
        break;
      case NETWORK_REDSTONE:
        skyStrifeUrl = SS_URL_REDSTONE;
        break;
    }

    return `${skyStrifeUrl}/match?asPlayer=&useExternalWallet=&match=${matchID}`;
  };

  console.log("matchUrl", getMatchURL());
  console.log("window.location.href", window.location.href);

  let html = ``;
  const buttons = [];
  if (!matchID || matchID === nullBytes32) {
    // if (playerTeam != tileTeam) {
    //   // Only the opposising team can start a battle
    // }

    buttons.push({
      text: "Start Battle",
      type: "action",
      action: startBattle,
      disabled: false,
    });
  } else {
    // NOTE: We have to always show the claim button even when the match hasn't been played
    // as the match status isn't indexed on the DS graph
    buttons.push({
      text: "Claim Win",
      type: "action",
      action: claimWin,
      disabled: false,
    });
  }

  if (matchID && matchID !== nullBytes32) {
    // html = `<a href="http://localhost:1337/match?asPlayer=&useExternalWallet=&match=${matchID}" target="_blank">Join Match</a>`;
    html = `<a href="${getMatchURL()}" target="_blank">Join Match</a>`;

    // Join battle button wasn't working properly so using <a> tag for now
    // buttons.push({
    //   text: "Join Battle",
    //   type: "action",
    //   action: joinBattle,
    //   disabled: false,
    // });

    // Show time until battle timesout
    const timeoutBlock = getData(
      selectedBuilding,
      getTileMatchTimeoutBlockKey(selectedBuilding.location.tile.id)
    );

    const remainingBlocks = timeoutBlock > block ? timeoutBlock - block : 0;
    const remainingTimeMs = remainingBlocks * BLOCK_TIME_SECS * 1000;

    html += `<p>Time remaining until attacker can claim win by default</p><h3>${formatTime(remainingTimeMs)}</h3>`;
  }

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

// -- Match Data

function getTileMatchKey(tileId) {
  return tileId + "_entityID";
}

function getTileMatchTimeoutBlockKey(tileId) {
  return tileId + "_matchTimeoutBlock";
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
