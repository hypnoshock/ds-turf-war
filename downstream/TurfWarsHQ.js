import ds from "downstream";

export default async function update(state) {
  const buildings = state.world?.buildings || [];
  const mobileUnit = getMobileUnit(state);

  console.log("state", state);

  const joinTeam = () => {
    if (!mobileUnit) {
      console.log("no selected unit");
      return;
    }

    const payload = ds.encodeCall("function join()", []);

    ds.dispatch({
      name: "ZONE_USE",
      args: [mobileUnit.id, payload],
    });
  };

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

            buttons: [
              {
                text: "Join Team",
                type: "action",
                action: joinTeam,
                disabled: !!!mobileUnit,
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
