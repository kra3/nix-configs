// Active-room tile: occupancy badge, warm tint when a light is on, the room's comfort word, and icon-over-value readings for temperature, humidity and light level, each icon coloured by how that reading feels.

const ICONS = { temperature: "mdi:thermometer", humidity: "mdi:water-percent", illuminance: "mdi:brightness-5" };
const QUIET = "color-mix(in srgb, var(--secondary-text-color) 70%, transparent)";
const INFO = "var(--info-color, #039be5)";
const WARN = "var(--warning-color, #ffa600)";
const COMFORT = { Comfortable: QUIET, Cool: INFO, Cold: INFO, Warm: WARN, Hot: "var(--error-color, #db4437)", Humid: WARN, Dry: WARN };

function reading(states, id, decimals) {
  const s = id && states[id];
  const v = s ? parseFloat(s.state) : NaN;
  if (!isFinite(v)) return null;
  return { v, num: v.toFixed(decimals), unit: s.attributes.unit_of_measurement || "" };
}

function roomModel(states, cfg) {
  const on = (id) => states[id]?.state === "on";
  const word = states[cfg.comfort]?.state;
  const comfort = COMFORT[word] ? { word, tone: COMFORT[word] } : null;
  const damp = word === "Humid" || word === "Dry";
  const lux = reading(states, cfg.illuminance, 0);
  const luxTone = lux && (lux.v < (cfg.dark_below ?? 20) ? INFO : lux.v < (cfg.dim_below ?? 150) ? "var(--secondary-text-color)" : WARN);
  const stats = [
    ["temperature", reading(states, cfg.temperature, 1), comfort && (damp ? QUIET : comfort.tone)],
    ["humidity", reading(states, cfg.humidity, 0), comfort && (damp ? comfort.tone : QUIET)],
    ["illuminance", lux, luxTone],
  ]
    .filter(([, r]) => r)
    .map(([kind, r, tone]) => ({ icon: ICONS[kind], num: r.num, unit: r.unit, tone }));
  const rgb = on(cfg.light) && states[cfg.light].attributes.rgb_color;
  return { stats, comfort, lit: on(cfg.light), rgb: rgb ? `rgb(${rgb.join(",")})` : null, occupied: on(cfg.presence) };
}

const esc = (t) => String(t).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

const STYLE = `
  :host { display: block; }
  ha-card { cursor: pointer; height: 100%; min-height: 108px; box-sizing: border-box; --c: var(--primary-color); transition: background 0.3s, filter 0.15s; }
  ha-card:active { filter: brightness(1.15); }
  ha-card.lit { --c: var(--state-light-active-color, var(--warning-color, #ffa600)); background: color-mix(in srgb, var(--c) 10%, var(--card-background-color, transparent)); }
  .tile { display: flex; flex-direction: column; justify-content: center; gap: 12px; flex: 1; box-sizing: border-box; padding: 12px; }
  .head { display: flex; align-items: center; gap: 12px; min-width: 0; }
  .ic { position: relative; width: 36px; height: 36px; border-radius: 50%; display: grid; place-items: center; flex: none; background: color-mix(in srgb, var(--c) 16%, transparent); color: var(--c); }
  .ic ha-icon { --mdc-icon-size: 20px; }
  .bd { position: absolute; top: -3px; right: -3px; width: 16px; height: 16px; border-radius: 50%; display: grid; place-items: center; background: var(--primary-color); color: var(--card-background-color, #fff); animation: pulse 2.4s ease-out infinite; }
  .bd ha-icon { --mdc-icon-size: 10px; }
  @keyframes pulse { 0% { box-shadow: 0 0 0 0 color-mix(in srgb, var(--primary-color) 55%, transparent); } 70%, 100% { box-shadow: 0 0 0 7px transparent; } }
  @media (prefers-reduced-motion: reduce) { .bd { animation: none; } }
  .txt { min-width: 0; }
  .name { font-size: 14.5px; font-weight: 500; color: var(--primary-text-color); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .cf { font-size: 12px; font-style: italic; font-weight: 400; color: var(--k); margin-top: 1px; }
  .st { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 6px 6px; opacity: 0.75; }
  .s { display: flex; align-items: center; gap: 3px; }
  .s ha-icon { --mdc-icon-size: 14px; color: var(--k, var(--secondary-text-color)); flex: none; }
  .v { font-size: 12px; font-weight: 400; color: var(--primary-text-color); white-space: nowrap; }
  .v small { font-size: 10px; color: var(--secondary-text-color); margin-left: 1px; }
`;

class RoomTileCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.presence) throw new Error("room-tile-card: presence is required");
    this._config = config;
    this._html = "";
    if (!this.shadowRoot) this.attachShadow({ mode: "open" });
  }

  getCardSize() {
    return 2;
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
    const comfort = m.comfort ? `<div class="cf" style="--k:${m.comfort.tone}">${esc(m.comfort.word)}</div>` : "";
    const stats = m.stats.length
      ? `<div class="st">${m.stats
          .map((k) => `<div class="s"${k.tone ? ` style="--k:${k.tone}"` : ""}><ha-icon icon="${k.icon}"></ha-icon><div class="v">${esc(k.num)}<small>${esc(k.unit)}</small></div></div>`)
          .join("")}</div>`
      : "";
    const html =
      `<ha-card class="${m.lit ? "lit" : ""}"${m.rgb ? ` style="--c:${m.rgb}"` : ""}><div class="tile"><div class="head"><div class="ic"><ha-icon icon="${esc(c.icon || "mdi:door")}"></ha-icon>` +
      `${m.occupied ? `<div class="bd"><ha-icon icon="mdi:account"></ha-icon></div>` : ""}</div>` +
      `<div class="txt"><div class="name">${esc(c.name || "")}</div>${comfort}</div></div>${stats}</div></ha-card>`;
    if (html !== this._html) {
      this._html = html;
      this.shadowRoot.innerHTML = `<style>${STYLE}</style>${html}`;
      const card = this.shadowRoot.querySelector("ha-card");
      card.addEventListener("pointerdown", () => {
        this._held = false;
        this._timer = setTimeout(() => {
          this._held = true;
          this._moreInfo(this._config.light || this._config.temperature || this._config.presence);
        }, 500);
      });
      for (const e of ["pointerup", "pointerleave", "pointercancel"]) card.addEventListener(e, () => clearTimeout(this._timer));
      card.addEventListener("click", () => this._tap());
    }
  }

  _moreInfo(entityId) {
    this.dispatchEvent(new CustomEvent("hass-more-info", { detail: { entityId }, bubbles: true, composed: true }));
  }

  _tap() {
    if (this._held) return;
    const c = this._config;
    if (c.light) this._hass.callService("light", "toggle", { entity_id: c.light });
    else this._moreInfo(c.temperature || c.presence);
  }
}

if (typeof customElements !== "undefined" && !customElements.get("room-tile-card")) {
  customElements.define("room-tile-card", RoomTileCard);
  window.customCards = window.customCards || [];
  window.customCards.push({
    type: "room-tile-card",
    name: "Room tile card",
    description: "Active room: occupancy, light state, comfort, temperature, humidity and light level.",
  });
}

if (typeof module !== "undefined") {
  module.exports = { roomModel };
}
