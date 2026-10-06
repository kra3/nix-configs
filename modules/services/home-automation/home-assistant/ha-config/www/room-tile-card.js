// Room tile: name plus temperature, humidity and light level on one line.

const DASH = "—";

function reading(states, id, decimals) {
  const s = id && states[id];
  const v = s ? parseFloat(s.state) : NaN;
  if (!isFinite(v)) return null;
  const unit = (s.attributes && s.attributes.unit_of_measurement) || "";
  const num = decimals === undefined ? String(Math.round(v * 10) / 10) : v.toFixed(decimals);
  return num + (unit === "lx" ? " lx" : unit);
}

function roomModel(states, cfg) {
  const on = (id) => !!id && !!states[id] && states[id].state === "on";
  const parts = [reading(states, cfg.temperature), reading(states, cfg.humidity, 0), reading(states, cfg.illuminance, 0)].filter(Boolean);
  const lightOn = on(cfg.light);
  if (lightOn) parts.unshift("Light on");
  return { line: parts.length ? parts.join(" · ") : DASH, active: on(cfg.presence) || lightOn };
}

const STYLE = `
  :host { display: block; }
  ha-card { cursor: pointer; }
  .tile { display: flex; align-items: center; gap: 12px; padding: 12px 14px; }
  .badge { width: 36px; height: 36px; border-radius: 50%; display: flex; align-items: center; justify-content: center; flex: none; background: color-mix(in srgb, var(--secondary-text-color) 18%, transparent); color: var(--secondary-text-color); }
  .badge.active { background: color-mix(in srgb, var(--primary-color) 22%, transparent); color: var(--primary-color); }
  .badge ha-icon { --mdc-icon-size: 20px; }
  .txt { min-width: 0; }
  .name { font-size: 14px; font-weight: 500; color: var(--primary-text-color); }
  .line { font-size: 12px; color: var(--secondary-text-color); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
`;

class RoomTileCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.temperature) throw new Error("room-tile-card: temperature is required");
    this._config = config;
    this._html = "";
    if (!this.shadowRoot) this.attachShadow({ mode: "open" });
  }

  getCardSize() {
    return 1;
  }

  getGridOptions() {
    return { columns: 6, min_columns: 3 };
  }

  set hass(hass) {
    this._hass = hass;
    if (this._config) this._render();
  }

  _render() {
    const c = this._config;
    const m = roomModel(this._hass.states, c);
    const html = `<ha-card><div class="tile"><div class="badge ${m.active ? "active" : ""}"><ha-icon icon="${c.icon || "mdi:door"}"></ha-icon></div><div class="txt"><div class="name"></div><div class="line"></div></div></div></ha-card>`;
    if (html !== this._html) {
      this._html = html;
      this.shadowRoot.innerHTML = `<style>${STYLE}</style>${html}`;
      this.shadowRoot.querySelector("ha-card").addEventListener("click", () => this._tap());
    }
    this.shadowRoot.querySelector(".name").textContent = c.name || "";
    this.shadowRoot.querySelector(".line").textContent = m.line;
  }

  _tap() {
    const entityId = this._config.light || this._config.temperature;
    this.dispatchEvent(new CustomEvent("hass-more-info", { detail: { entityId }, bubbles: true, composed: true }));
  }
}

if (typeof customElements !== "undefined" && !customElements.get("room-tile-card")) {
  customElements.define("room-tile-card", RoomTileCard);
  window.customCards = window.customCards || [];
  window.customCards.push({
    type: "room-tile-card",
    name: "Room tile card",
    description: "Room name with temperature, humidity and light level.",
  });
}

if (typeof module !== "undefined") {
  module.exports = { reading, roomModel };
}
