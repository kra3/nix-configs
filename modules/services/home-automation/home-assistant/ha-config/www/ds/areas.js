const SENSOR = { temperature: "temperature", humidity: "humidity", illuminance: "illuminance", carbon_dioxide: "co2", power: "power" };
const BINARY = { occupancy: "occupancy", presence: "occupancy", motion: "motion", door: "openings", window: "openings", opening: "openings", garage_door: "openings" };
const DOMAIN = { light: "lights", switch: "switches", media_player: "media", climate: "climate", cover: "covers", fan: "fans", lock: "locks", camera: "cameras" };

export const emptyRoom = () => ({ lights: [], switches: [], media: [], climate: [], covers: [], fans: [], locks: [], cameras: [], occupancy: [], motion: [], openings: [], temperature: [], humidity: [], illuminance: [], co2: [], power: [] });

const nameOf = (hass, id) => hass.states[id].attributes.friendly_name || id;

const NOT_PERSON = /_(cat|dog|all)_occupancy$/;
const cache = new WeakMap();

function index(hass) {
  const ents = hass.entities || {};
  const hit = cache.get(ents);
  if (hit && hit.devices === hass.devices) return hit;
  const byArea = new Map();
  const byDev = new Map();
  const push = (m, k, id) => (m.get(k) || m.set(k, []).get(k)).push(id);
  for (const [id, e] of Object.entries(ents)) {
    if (e.device_id) push(byDev, e.device_id, id);
    const area = e.area_id || (e.device_id && hass.devices?.[e.device_id]?.area_id);
    if (area) push(byArea, area, id);
  }
  const idx = { devices: hass.devices, byArea, byDev };
  cache.set(ents, idx);
  return idx;
}

export const cameraMotion = (hass, id) => {
  const dev = hass.entities?.[id]?.device_id;
  return !!dev && hass.states[id]?.attributes.device_class === "motion" && (index(hass).byDev.get(dev) || []).some((o) => o.startsWith("camera."));
};

export function roomEntities(hass, areaId, { exclude = [] } = {}) {
  const out = emptyRoom();
  const skip = new Set(exclude.filter(Boolean));
  const members = new Set();
  for (const id of skip) for (const m of hass.states[id]?.attributes?.entity_id || []) members.add(m);
  const mine = new Set();
  for (const id of index(hass).byArea.get(areaId) || []) {
    const e = hass.entities[id];
    if (!e.entity_category && !e.hidden && hass.states[id]) mine.add(id);
  }
  for (const id of mine) for (const m of hass.states[id].attributes.entity_id || []) if (mine.has(m)) members.add(m);
  for (const id of mine) {
    if (skip.has(id) || members.has(id)) continue;
    const dom = id.split(".")[0];
    const dc = hass.states[id].attributes.device_class;
    const key = dom === "sensor" ? SENSOR[dc] : dom === "binary_sensor" ? BINARY[dc] : DOMAIN[dom];
    if (dom === "binary_sensor" && (NOT_PERSON.test(id) || cameraMotion(hass, id))) continue;
    if (key) out[key].push(id);
  }
  for (const list of Object.values(out)) list.sort((a, b) => nameOf(hass, a).localeCompare(nameOf(hass, b)) || a.localeCompare(b));
  return out;
}

const TOGGLE = ["light", "fan", "cover"];
const CONTROLS = ["lights", "switches", "fans", "covers", "media", "locks", "climate"];
const SENSORS = ["temperature", "humidity", "illuminance", "co2"];
const OPENING = { on: "Open", off: "Closed" };
const ONOFF = { on: "On", off: "Off" };

const unit = (s) => (s.attributes.unit_of_measurement ? ` ${s.attributes.unit_of_measurement}` : "");

// Switches can cut power, so area-discovered ones are read-only rows.
export function areaRows(hass, areaId, exclude = []) {
  const r = roomEntities(hass, areaId, { exclude });
  const st = (id) => hass.states[id];
  const fmt = (id, map = {}) => (hass.formatEntityState ? hass.formatEntityState(st(id)) : map[st(id).state] || `${st(id).state}${unit(st(id))}`);
  const power = (id) => {
    const dev = hass.entities[id]?.device_id;
    const p = dev && (index(hass).byDev.get(dev) || []).find((o) => o !== id && st(o)?.attributes.device_class === "power" && !isNaN(st(o).state));
    return p ? ` \u00b7 ${fmt(p)}` : "";
  };
  const row = (id, extra) => ({ id, name: st(id).attributes.friendly_name || id, ...extra });
  const controls = CONTROLS.flatMap((k) => r[k]).map((id) => {
    const dom = id.split(".")[0];
    if (TOGGLE.includes(dom)) return row(id, { text: "", toggle: dom });
    if (dom === "switch") return row(id, { text: fmt(id, ONOFF) + power(id), readonly: true });
    return row(id, { text: fmt(id) });
  });
  const openings = r.openings.map((id) => row(id, { text: fmt(id, OPENING) }));
  const sensors = SENSORS.flatMap((k) => r[k]).map((id) => row(id, { text: fmt(id) }));
  return { controls, openings, sensors };
}
