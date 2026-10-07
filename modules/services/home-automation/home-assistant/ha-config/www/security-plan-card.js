// Floor plan: fixed room rectangles, devices placed by area, so added or removed devices appear without edits.

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const OPEN_CLASSES = ["door", "window", "garage_door", "opening"];
const GONE = ["unknown", "unavailable"];
const NOT_PERSON = /_(cat|dog|all)_occupancy$/;

function areaFor(hass, id, cfg) {
  const over = cfg && cfg.area_override && cfg.area_override[id];
  if (over) return over;
  const e = hass.entities && hass.entities[id];
  const dev = e && e.device_id && hass.devices && hass.devices[e.device_id];
  const areaId = (e && e.area_id) || (dev && dev.area_id);
  return (areaId && hass.areas && hass.areas[areaId] && hass.areas[areaId].name) || "";
}

function badgeFor(s, armed) {
  const id = s.entity_id;
  const name = s.attributes.friendly_name || id;
  if (id.startsWith("camera.")) return { id, name, icon: "mdi:cctv", tone: GONE.includes(s.state) ? "dead" : "cam", kind: "camera" };
  if (id.startsWith("lock.")) {
    if (GONE.includes(s.state)) return { id, name, icon: "mdi:lock-alert", tone: "dead", kind: "lock" };
    const bad = ["unlocked", "open", "jammed"].includes(s.state);
    return { id, name, icon: bad ? "mdi:lock-open-variant" : "mdi:lock", tone: bad ? "open" : "ok", kind: "lock" };
  }
  const cls = s.attributes.device_class;
  const win = cls === "window";
  if (GONE.includes(s.state)) return { id, name, icon: "mdi:help-circle-outline", tone: "dead", kind: "opening" };
  const on = s.state === "on";
  return {
    id,
    name,
    icon: win ? (on ? "mdi:window-open-variant" : "mdi:window-closed-variant") : on ? "mdi:door-open" : "mdi:door-closed",
    tone: on ? (armed ? "alert" : "open") : "ok",
    kind: "opening",
  };
}

function planModel(states, areaOf, cfg) {
  const all = Object.values(states);
  const alarm = cfg.alarm ? states[cfg.alarm] : all.find((s) => s.entity_id.startsWith("alarm_control_panel."));
  const armed = !!alarm && alarm.state.startsWith("armed_");
  const rooms = (cfg.rooms || []).map((r) => {
    const areas = new Set([].concat(r.areas || r.area || []));
    const extra = new Set(r.entities || []);
    const mine = all.filter((s) => extra.has(s.entity_id) || (areas.has(areaOf(s.entity_id)) && !(cfg.hide || []).includes(s.entity_id)));
    const badges = mine
      .filter((s) => {
        const id = s.entity_id;
        if (id.startsWith("camera.") || id.startsWith("lock.")) return true;
        return id.startsWith("binary_sensor.") && OPEN_CLASSES.includes(s.attributes.device_class);
      })
      .map((s) => badgeFor(s, armed))
      .sort((a, b) => a.kind.localeCompare(b.kind) || a.name.localeCompare(b.name));
    const presenceIds = new Set([
      ...(r.presence || []),
      ...mine.filter((s) => s.entity_id.startsWith("binary_sensor.") && s.attributes.device_class === "occupancy" && !NOT_PERSON.test(s.entity_id)).map((s) => s.entity_id),
    ]);
    const occupied = [...presenceIds].some((id) => states[id] && states[id].state === "on");
    const person = mine.some((s) => /^binary_sensor\..*_person_occupancy$/.test(s.entity_id) && s.state === "on");
    const posOf = cfg.positions || {};
    for (const b of badges) if (posOf[b.id]) b.pos = posOf[b.id];
    const status = badges.some((b) => b.tone === "alert") ? "alert" : badges.some((b) => b.tone === "open") ? "open" : occupied ? "occ" : "";
    return { name: r.name || [...areas][0] || "", rect: r.rect, outdoor: !!r.outdoor, badges, occupied, person, status };
  });
  return { rooms, armed };
}

function planHtml(m, size, image) {
  const [W, H] = size;
  const pct = (v, t) => ((v / t) * 100).toFixed(3) + "%";
  const room = (r) => {
    const [x, y, w, h] = r.rect;
    const badges = r.badges
      .filter((b) => !b.pos)
      .map((b) => `<button class="b ${b.tone}" title="${esc(b.name)}" data-id="${esc(b.id)}"><ha-icon icon="${b.icon}"></ha-icon></button>`)
      .join("");
    return `<div class="room ${r.status} ${r.outdoor ? "out" : ""} ${r.person ? "person" : ""}" style="left:${pct(x, W)};top:${pct(y, H)};width:${pct(w, W)};height:${pct(h, H)}">
      <div class="nm">${esc(r.name)}${r.occupied ? '<span class="dot"></span>' : ""}</div><div class="bs">${badges}</div></div>`;
  };
  const walls = m.rooms
    .flatMap((r) => r.badges.filter((b) => b.pos))
    .map(
      (b) =>
        `<button class="b w ${b.tone}" title="${esc(b.name)}" data-id="${esc(b.id)}" style="left:${pct(b.pos[0], W)};top:${pct(b.pos[1], H)}"><ha-icon icon="${b.icon}"></ha-icon></button>`
    )
    .join("");
  const legend = `<div class="legend"><span><i class="k occ"></i>Occupied</span><span><i class="k open"></i>Open</span><span><i class="k alert"></i>Open while armed</span><span><i class="k cam"></i>Camera</span></div>`;
  return `<div class="plan ${image ? "img" : ""}" style="aspect-ratio:${W}/${H};${image ? `--img:url(${esc(image)})` : ""}">${m.rooms.map(room).join("")}${walls}</div>${legend}`;
}

const STYLE = `
  :host { display: block; }
  ha-card { padding: 10px; }
  .plan { position: relative; width: 100%; container: plan / inline-size; }
  .room { position: absolute; box-sizing: border-box; border: 2px solid var(--divider-color); background: var(--secondary-background-color); border-radius: 4px; padding: 3px 5px; overflow: hidden; container: room / inline-size; }
  .plan.img::before { content: ""; position: absolute; inset: 0; background: var(--secondary-text-color); opacity: 0.6; -webkit-mask: var(--img) center / 100% 100% no-repeat; mask: var(--img) center / 100% 100% no-repeat; }
  .plan.img .room { border: 0; background: transparent; border-radius: 0; }
  .plan.img .room.occ { background: color-mix(in srgb, var(--primary-color) 24%, transparent); }
  .plan.img .room.open { box-shadow: inset 0 0 0 2px #ffb300; }
  .plan.img .room.alert { box-shadow: inset 0 0 0 2px var(--error-color, #f44336); background: color-mix(in srgb, var(--error-color, #f44336) 16%, transparent); }
  .room.out { background: transparent; border-style: dashed; opacity: 0.8; }
  .room.occ { background: color-mix(in srgb, var(--primary-color) 20%, var(--secondary-background-color)); }
  .room.open { border-color: #ffb300; }
  .room.alert { border-color: var(--error-color, #f44336); background: color-mix(in srgb, var(--error-color, #f44336) 14%, var(--secondary-background-color)); }
  .room.person { animation: pulse 1.6s ease-in-out infinite; }
  @keyframes pulse { 50% { box-shadow: inset 0 0 0 2px var(--error-color, #f44336); } }
  .nm { font-size: 11px; font-weight: 600; color: var(--secondary-text-color); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .dot { display: inline-block; width: 7px; height: 7px; margin-left: 5px; border-radius: 50%; background: var(--primary-color); }
  .bs { display: flex; flex-wrap: wrap; gap: 2px; margin-top: 2px; }
  .b { border: 0; padding: 2px; border-radius: 6px; cursor: pointer; background: transparent; color: var(--secondary-text-color); line-height: 0; }
  .b ha-icon { --mdc-icon-size: 20px; }
  .b.open { color: #ffb300; background: color-mix(in srgb, #ffb300 18%, transparent); }
  .b.alert { color: var(--error-color, #f44336); background: color-mix(in srgb, var(--error-color, #f44336) 18%, transparent); }
  .b.cam { color: var(--primary-color); }
  .b.dead { opacity: 0.45; }
  .b.w { position: absolute; transform: translate(-50%, -50%); z-index: 1; background: var(--card-background-color); border-radius: 50%; }
  .b.w.open { background: color-mix(in srgb, #ffb300 35%, var(--card-background-color)); }
  .b.w.alert { background: color-mix(in srgb, var(--error-color, #f44336) 35%, var(--card-background-color)); }
  .legend { display: flex; flex-wrap: wrap; gap: 4px 14px; margin-top: 8px; font-size: 11px; color: var(--secondary-text-color); }
  .legend .k { display: inline-block; width: 10px; height: 10px; margin-right: 5px; border-radius: 3px; vertical-align: -1px; }
  .k.occ { background: color-mix(in srgb, var(--primary-color) 45%, transparent); }
  .k.open { box-shadow: inset 0 0 0 2px #ffb300; }
  .k.alert { box-shadow: inset 0 0 0 2px var(--error-color, #f44336); }
  .k.cam { background: var(--primary-color); border-radius: 50%; }
  @container plan (max-width: 560px) {
    .nm { font-size: 9px; }
    .room { padding: 2px 3px; }
    .b { padding: 1px; }
    .b ha-icon { --mdc-icon-size: 16px; }
  }
  @container room (max-width: 64px) { .nm { font-size: 8px; } }
  @container room (max-width: 34px) { .nm { display: none; } .b ha-icon { --mdc-icon-size: 14px; } }
`;

class SecurityPlanCard extends HTMLElement {
  setConfig(config) {
    this._config = config || {};
    this._html = "";
    if (!this.shadowRoot) this.attachShadow({ mode: "open" });
  }

  getCardSize() {
    return 6;
  }

  getGridOptions() {
    return { columns: 12, min_columns: 6 };
  }

  set hass(hass) {
    this._hass = hass;
    if (this._config) this._render();
  }

  _render() {
    const cfg = this._config;
    const html = planHtml(planModel(this._hass.states, (id) => areaFor(this._hass, id, cfg), cfg), cfg.size || [730, 620], cfg.image);
    if (html === this._html) return;
    this._html = html;
    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card>${html}</ha-card>`;
    for (const el of this.shadowRoot.querySelectorAll(".b")) {
      el.addEventListener("click", () => this.dispatchEvent(new CustomEvent("hass-more-info", { detail: { entityId: el.dataset.id }, bubbles: true, composed: true })));
    }
  }
}

if (typeof customElements !== "undefined" && !customElements.get("security-plan-card")) {
  customElements.define("security-plan-card", SecurityPlanCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "security-plan-card", name: "Security floor plan", description: "Rooms with doors, windows, locks, cameras and presence placed by area." });
}

if (typeof module !== "undefined") {
  module.exports = { planModel, planHtml, badgeFor };
}
