import ds from 'downstream';

export default async function update(state) {

    const mobileUnit = getMobileUnit(state);
    const buildings = state.world?.buildings || [];

    const counterBuildings = getBuildingsByType(buildings, "Counter")[0];
    const counterTiles = getTilesByTeam();


    const IncrementCounter = () => {
        const payload = ds.encodeCall("function increment()", []);
    
        ds.dispatch({
            name: "BUILDING_USE",
            args: [counterBuildings.id, mobileUnit.id, payload],
        });
    };


    // uncomment this to browse the state object in browser console
    // this will be logged when selecting a unit and then selecting an instance of this building
    //logState(state);

    const selectedTile = getSelectedTile(state);
    const selectedBuilding = selectedTile && getBuildingOnTile(state, selectedTile);
    const canCraft = selectedBuilding && inputsAreCorrect(state, selectedBuilding)
    // uncomment this to be restrictve about which units can craft
    // this is a client only check - to enforce it in contracts make
    // similar changes in BasicFactory.sol
    //    && unitIsFriendly(state, selectedBuilding)
        ;

    // const craft = () => {
    //     const mobileUnit = getMobileUnit(state);

    //     if (!mobileUnit) {
    //         console.log('no selected unit');
    //         return;
    //     }

    //     ds.dispatch({
    //         name: 'BUILDING_USE',
    //         args: [selectedBuilding.id, mobileUnit.id, []],
    //     });

    //     console.log('Craft dispatched');
    // };

    const count = getDataInt(counterBuildings, "count");

    return {
        version: 1,
        // map: counterBuildings.map((b) => ({
        //     type: "building",
        //     id: `${b.id}`,
        //     key: "labelText",
        //     value: `${count % 100}`,
        // })),
        components: [
            {
                id: "counter",
                type: "building",
                content: [
                    {
                        id: "default",
                        type: "inline",
                        html: ``,

                        buttons: [
                            {
                                // text: "Increment Counter",
                                // type: "action",
                                // action: IncrementCounter,
                            },
                        ],
                    },
                ],
            },
        ],
    };
}

const getBuildingsByType = (buildingsArray, type) => {
    return buildingsArray.filter(
        (building) =>
            building.kind?.name?.value.toLowerCase().trim() ==
            type.toLowerCase().trim(),
    );
};

// const getTilesByTeam = (tilesArray, team)=> {
//     return state.world.tiles.filter(
//         (building) =>
//             building.kind?.name?.value.toLowerCase().trim() ==
//             type.toLowerCase().trim(),
//     );
// };

function getMobileUnit(state) {
    return state?.selected?.mobileUnit;
}

function getSelectedTile(state) {
    const tiles = state?.selected?.tiles || {};
    return tiles && tiles.length === 1 ? tiles[0] : undefined;
}

function getBuildingOnTile(state, tile) {
    return (state?.world?.buildings || []).find((b) => tile && b.location?.tile?.id === tile.id);
}

// returns an array of items the building expects as input
function getRequiredInputItems(building) {
    return building?.kind?.inputs || [];
}

// search through all the bags in the world to find those belonging to this building
function getBuildingBags(state, building) {
    return building ? (state?.world?.bags || []).filter((bag) => bag.equipee?.node.id === building.id) : [];
}

// get building input slots
function getInputSlots(state, building) {
    // inputs are the bag with key 0 owned by the building
    const buildingBags = getBuildingBags(state, building);
    const inputBag = buildingBags.find((bag) => bag.equipee.key === 0);

    // slots used for crafting have sequential keys startng with 0
    return inputBag && inputBag.slots.sort((a, b) => a.key - b.key);
}

// are the required craft input items in the input slots?
function inputsAreCorrect(state, building) {
    const requiredInputItems = getRequiredInputItems(building);
    const inputSlots = getInputSlots(state, building);

    return (
        inputSlots &&
        inputSlots.length >= requiredInputItems.length &&
        requiredInputItems.every(
            (requiredItem) =>
                inputSlots[requiredItem.key].item.id == requiredItem.item.id &&
                inputSlots[requiredItem.key].balance == requiredItem.balance
        )
    );
}

function logState(state) {
    console.log('State sent to pluging:', state);
}

const friendlyPlayerAddresses = [
    // 0x402462EefC217bf2cf4E6814395E1b61EA4c43F7
];

function unitIsFriendly(state, selectedBuilding) {
    const mobileUnit = getMobileUnit(state);
    return (
        unitIsBuildingOwner(mobileUnit, selectedBuilding) ||
        unitIsBuildingAuthor(mobileUnit, selectedBuilding) ||
        friendlyPlayerAddresses.some((addr) => unitOwnerConnectedToWallet(state, mobileUnit, addr))
    );
}

function unitIsBuildingOwner(mobileUnit, selectedBuilding) {
    //console.log('unit owner id:',  mobileUnit?.owner?.id, 'building owner id:', selectedBuilding?.owner?.id);
    return mobileUnit?.owner?.id && mobileUnit?.owner?.id === selectedBuilding?.owner?.id;
}

function unitIsBuildingAuthor(mobileUnit, selectedBuilding) {
    //console.log('unit owner id:',  mobileUnit?.owner?.id, 'building author id:', selectedBuilding?.kind?.owner?.id);
    return mobileUnit?.owner?.id && mobileUnit?.owner?.id === selectedBuilding?.kind?.owner?.id;
}

function unitOwnerConnectedToWallet(state, mobileUnit, walletAddress) {
    //console.log('Checking player:',  state?.player, 'controls unit', mobileUnit, walletAddress);
    return mobileUnit?.owner?.id == state?.player?.id && state?.player?.addr == walletAddress;
}


function getDataInt(buildingInstance, key) {
    var hexVal = getData(buildingInstance, key);
    return typeof hexVal === "string" ? parseInt(hexVal, 16) : 0;
}

function getData(buildingInstance, key) {
    return getKVPs(buildingInstance)[key];
}

function getKVPs(buildingInstance) {
    return (buildingInstance.allData || []).reduce((kvps, data) => {
        kvps[data.name] = data.value;
        return kvps;
    }, {});
}

// the source for this code is on github where you can find other example buildings:
// https://github.com/playmint/ds/tree/main/contracts/src/example-plugins
