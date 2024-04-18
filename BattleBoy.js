import ds from "downstream";

export default async function update(state) {
  //   const buildings = state.world?.buildings || [];
  const mobileUnit = getMobileUnit(state);
  const selectedTile = getSelectedTile(state);
  const selectedBuilding =
    selectedTile && getBuildingOnTile(state, selectedTile);

  const implementationAddr = selectedBuilding.kind.implementation.id.slice(-40);
  console.log("implementationAddr", implementationAddr);

  const buySeasonPass = () => {
    const payload = ds.encodeCall("function buySeasonPass()", []);
    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, mobileUnit.id, payload],
    });
  };

  const startWar = () => {
    const payload = ds.encodeCall("function startWar()", []);
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
                text: "Start War",
                type: "action",
                action: startWar,
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
