const SENSOR = { temperature: "temperature", humidity: "humidity", illuminance: "illuminance", carbon_dioxide: "co2", power: "power" };
const BINARY = { occupancy: "occupancy", presence: "occupancy", motion: "motion", door: "openings", window: "openings", opening: "openings", garage_door: "openings" };
const DOMAIN = { light: "lights", switch: "switches", media_player: "media", climate: "climate", cover: "covers", fan: "fans", lock: "locks", camera: "cameras" };

export const emptyRoom = () => ({ lights: [], switches: [], media: [], climate: [], covers: [], fans: [], locks: [], cameras: [], occupancy: [], motion: [], openings: [], temperature: [], humidity: [], illuminance: [], co2: [], power: [] });

const nameOf = (hass, id) => hass.states[id].attributes.friendly_name || id;

export function roomEntities(hass, areaId, { exclude = [] } = {}) {
  const out = emptyRoom();
  const skip = new Set(exclude.filter(Boolean));
  const members = new Set();
  for (const id of skip) for (const m of hass.states[id]?.attributes?.entity_id || []) members.add(m);
  const mine = new Set();
  for (const [id, e] of Object.entries(hass.entities || {})) {
    const area = e.area_id || (e.device_id && hass.devices?.[e.device_id]?.area_id);
    if (area === areaId && !e.entity_category && !e.hidden && hass.states[id]) mine.add(id);
  }
  for (const id of mine) for (const m of hass.states[id].attributes.entity_id || []) if (mine.has(m)) members.add(m);
  for (const id of mine) {
    if (skip.has(id) || members.has(id)) continue;
    const dom = id.split(".")[0];
    const dc = hass.states[id].attributes.device_class;
    const key = dom === "sensor" ? SENSOR[dc] : dom === "binary_sensor" ? BINARY[dc] : DOMAIN[dom];
    if (key) out[key].push(id);
  }
  for (const list of Object.values(out)) list.sort((a, b) => nameOf(hass, a).localeCompare(nameOf(hass, b)) || a.localeCompare(b));
  return out;
}
