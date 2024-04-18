import ds from "downstream";

export default async function update(state) {
  //   const buildings = state.world?.buildings || [];
  const mobileUnit = getMobileUnit(state);
  const selectedTile = getSelectedTile(state);
  const selectedBuilding =
    selectedTile && getBuildingOnTile(state, selectedTile);

  const implementationAddr = selectedBuilding.kind.implementation.id.slice(-40);
  console.log("implementationAddr", implementationAddr);
  console.log("selectedBuilding", selectedBuilding);

  const matchID = getData(selectedBuilding, getTileMatchKey(selectedBuilding));
  const winner = getData(selectedBuilding, getTileWinnerKey(selectedBuilding));

  console.log("matchID", matchID);
  console.log("winner", winner);

  const buySeasonPass = () => {
    const payload = ds.encodeCall("function buySeasonPass()", []);
    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, mobileUnit.id, payload],
    });
  };

  const startBattle = () => {
    const payload = ds.encodeCall("function startBattle()", []);
    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, mobileUnit.id, payload],
    });
  };

  const claimWin = () => {
    const judgeBuildingInstance = state.world?.buildings.find(
      (b) => b.kind?.name?.value == "Judge"
    );

    if (!judgeBuildingInstance) {
      console.error("Judge building not found");
      return;
    }

    const payload = ds.encodeCall("function claimWin(bytes24)", [
      judgeBuildingInstance.id,
    ]);
    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, mobileUnit.id, payload],
    });
  };

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
            html: ``,

            buttons: [
              {
                text: "Buy Season Pass",
                type: "action",
                action: buySeasonPass,
                disabled: false,
              },
              {
                text: "Start Battle",
                type: "action",
                action: startBattle,
                disabled: false,
              },
              {
                text: "Claim Win",
                type: "action",
                action: claimWin,
                disabled: false,
              },
            ],
          },
        ],
      },
    ],
  };
}

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

function getTileMatchKey(buildingInstance) {
  return buildingInstance.location.tile.id + "_entityID";
}

function getTileWinnerKey(buildingInstance) {
  return buildingInstance.location.tile.id + "_winner";
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
