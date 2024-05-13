import ds from "downstream";

const billboardName = "How To Play Turf Wars Lite";
const billboardImage = "https://i.imgur.com/ATHk8Qv.png";

export default async function update({ selected, world, player }) {
  const billboardBuilding = (world?.buildings || []).find(
    (b) => b.kind?.name?.value === billboardName
  );
  const mapObj = [];
  if (billboardBuilding) {
    mapObj.push({
      type: "building",
      key: "image",
      id: `${billboardBuilding.id}`,
      value: `${billboardImage}`,
    });
  }
  return {
    version: 1,
    map: mapObj,
    components: [
      {
        type: "building",
        id: "rules",
        content: [
          {
            id: "default",
            type: "inline",
            html: ` Fight to paint the map!
                                
                            <ul style="padding-left: 30px;">
                                <li>Move to an unpainted tile to paint it for your team</li>
                                <li>Building a &quot;Turf Wars Base&quot; will paint all unpainted squares in a large radius</li>
                            </ul>
                                The team with the most painted tiles when the timer ends is the winner`,
          },
        ],
      },
    ],
  };
}
