// Room climate tile: a status-tinted icon with a badge when the room is off its comfort range, the room name, the comfort word and temperature, humidity and dew point readings with glyphs; tapping opens a popup with the comfort reason, a 24 h or 7 d history graph and a link to the sensor details.

const STYLE = `
  :host { display: block; }
  ha-card { cursor: pointer; }
  .tile { display: flex; align-items: center; gap: 12px; padding: 12px 14px; }
  .ic { position: relative; width: 40px; height: 40px; border-radius: 50%; display: grid; place-items: center; flex: none; background: color-mix(in srgb, var(--c) 20%, transparent); color: var(--c); }
  .ic ha-icon { --mdc-icon-size: 22px; }
  .bd { position: absolute; top: -3px; right: -3px; width: 18px; height: 18px; border-radius: 50%; display: grid; place-items: center; background: var(--c); color: var(--card-background-color, #fff); }
  .bd ha-icon { --mdc-icon-size: 12px; }
  .txt { min-width: 0; }
  .name { font-size: 14px; font-weight: 500; color: var(--primary-text-color); }
  .line { display: flex; flex-wrap: wrap; align-items: center; gap: 2px 12px; font-size: 12px; color: var(--secondary-text-color); margin-top: 2px; }
  .st { font-weight: 600; color: var(--c); }
  .rd { display: inline-flex; align-items: center; gap: 3px; white-space: nowrap; }
  .rd ha-icon { --mdc-icon-size: 14px; }
`;

const POPUP_STYLE = `
  .crc-overlay { position: fixed; inset: 0; z-index: 9; background: rgba(0, 0, 0, 0.6); display: flex; align-items: center; justify-content: center; padding: 16px; }
  .crc-sheet { width: min(520px, 100%); max-height: 90vh; overflow: auto; background: var(--card-background-color, #1c1c1c); border-radius: 16px; padding: 8px 16px 16px; box-sizing: border-box; }
  .crc-head { display: flex; justify-content: space-between; align-items: center; }
  .crc-title { font-size: 16px; font-weight: 600; color: var(--primary-text-color); }
  .crc-close { background: none; border: 0; color: var(--secondary-text-color); font-size: 26px; line-height: 1; cursor: pointer; min-width: 44px; min-height: 44px; }
  .crc-sum { display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px 16px; }
  .crc-word { font-size: 20px; font-weight: 600; color: var(--c); }
  .crc-rd { display: flex; flex-wrap: wrap; gap: 2px 14px; font-size: 14px; color: var(--primary-text-color); }
  .crc-rd .rd { display: inline-flex; align-items: center; gap: 3px; white-space: nowrap; }
  .crc-rd ha-icon { --mdc-icon-size: 16px; color: var(--secondary-text-color); }
  .crc-why { margin-top: 4px; font-size: 13px; color: var(--secondary-text-color); }
  .crc-tabs { display: flex; gap: 8px; margin: 12px 0 4px; }
  .crc-tabs button { min-height: 44px; min-width: 64px; border-radius: 22px; border: 1px solid var(--divider-color); background: none; color: var(--secondary-text-color); font: inherit; font-size: 13px; cursor: pointer; }
  .crc-tabs button.on { background: var(--primary-color); border-color: var(--primary-color); color: var(--text-primary-color, #fff); }
  .crc-note { margin-top: 8px; font-size: 12px; color: var(--secondary-text-color); }
  .crc-link { margin-top: 12px; min-height: 44px; padding: 0 4px; background: none; border: 0; color: var(--primary-color); font: inherit; font-size: 13px; font-weight: 600; cursor: pointer; }
`;

const TONES = {
  Comfortable: ["var(--success-color, #43a047)", ""],
  Cool: ["var(--info-color, #039be5)", "mdi:snowflake"],
  Cold: ["var(--info-color, #039be5)", "mdi:snowflake-alert"],
  Warm: ["var(--warning-color, #ffa600)", "mdi:white-balance-sunny"],
  Hot: ["var(--error-color, #db4437)", "mdi:thermometer-alert"],
  Humid: ["var(--warning-color, #ffa600)", "mdi:water"],
  Dry: ["var(--warning-color, #ffa600)", "mdi:water-off"],
};
const INACTIVE = "var(--state-inactive-color, var(--secondary-text-color))";

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

class ClimateRoomCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.comfort) throw new Error("climate-room-card: comfort is required");
    this._config = config;
    this._html = "";
    if (!this.shadowRoot) this.attachShadow({ mode: "open" });
  }

  getCardSize() {
    return 1;
  }

  set hass(hass) {
    this._hass = hass;
    if (this._config) this._render();
  }

  _reading(id, icon, decimals) {
    const s = id && this._hass.states[id];
    const v = s ? parseFloat(s.state) : NaN;
    if (!isFinite(v)) return "";
    const unit = (s.attributes && s.attributes.unit_of_measurement) || "";
    return `<span class="rd"><ha-icon icon="${icon}"></ha-icon>${esc(v.toFixed(decimals))}${unit ? ` ${esc(unit)}` : ""}</span>`;
  }

  _render() {
    const c = this._config;
    const s = this._hass.states[c.comfort];
    const word = s && !["unavailable", "unknown", "none"].includes(s.state) ? s.state : null;
    const [color, badge] = word ? TONES[word] || [INACTIVE, ""] : [INACTIVE, ""];
    const line = word
      ? `<span class="st">${esc(word)}</span>${this._reading(c.temperature, "mdi:thermometer", 1)}${this._reading(c.humidity, "mdi:water-percent", 0)}${this._reading(c.dew, "mdi:water-thermometer-outline", 1)}${c.approx ? `<span class="rd">approx.</span>` : ""}`
      : `<span class="st">Not reporting</span>`;
    const html =
      `<ha-card><div class="tile" style="--c:${color}"><div class="ic"><ha-icon icon="${esc(c.icon || "mdi:thermometer")}"></ha-icon>` +
      `${badge ? `<div class="bd"><ha-icon icon="${badge}"></ha-icon></div>` : ""}</div>` +
      `<div class="txt"><div class="name">${esc(c.name || "")}</div><div class="line">${line}</div></div></div></ha-card>`;
    if (html !== this._html) {
      this._html = html;
      this.shadowRoot.innerHTML = `<style>${STYLE}</style>${html}`;
      this.shadowRoot.querySelector("ha-card").addEventListener("click", () => this._open());
    }
  }

  _num(id) {
    const s = id && this._hass.states[id];
    const v = s ? parseFloat(s.state) : NaN;
    return isFinite(v) ? v : null;
  }

  _reason(word) {
    const c = this._config;
    const t = this._num(c.temperature);
    const h = this._num(c.humidity);
    const low = this._num("input_number.climate_temp_low");
    const high = this._num(this._hass.states["sensor.season"]?.state === "summer" ? "input_number.climate_temp_high_summer" : "input_number.climate_temp_high");
    const ceil = this._num("sensor.humidity_ceiling");
    if (word === "Comfortable") return low !== null && high !== null ? `Within the ${low}–${high} °C comfort range` : "";
    if (t !== null && low !== null && t < low) return `${t.toFixed(1)} °C is below the ${low} °C minimum`;
    if (t !== null && high !== null && t > high) return `${t.toFixed(1)} °C is above the ${high} °C maximum`;
    if (h !== null && ceil !== null && h > ceil) return `Humidity ${Math.round(h)} % is over the ${Math.round(ceil)} % ceiling`;
    return "";
  }

  async _open() {
    if (this._overlay) return;
    const c = this._config;
    if (!document.getElementById("crc-style")) {
      const st = document.createElement("style");
      st.id = "crc-style";
      st.textContent = POPUP_STYLE;
      document.head.appendChild(st);
    }
    const ov = document.createElement("div");
    ov.className = "crc-overlay";
    ov.innerHTML = `<div class="crc-sheet" role="dialog" aria-modal="true"><div class="crc-head"><span class="crc-title"></span><button class="crc-close" aria-label="Close">×</button></div><div class="crc-body"></div></div>`;
    ov.querySelector(".crc-title").textContent = c.name || "";
    const close = () => {
      document.removeEventListener("keydown", onKey);
      ov.remove();
      this._overlay = null;
    };
    const onKey = (e) => {
      if (e.key === "Escape") close();
    };
    ov.addEventListener("click", (e) => {
      if (e.target === ov) close();
    });
    ov.querySelector(".crc-close").addEventListener("click", close);
    document.addEventListener("keydown", onKey);
    document.body.appendChild(ov);
    this._overlay = ov;
    this._hours = 24;
    await this._paintPopup();
  }

  async _paintPopup() {
    const ov = this._overlay;
    if (!ov) return;
    const c = this._config;
    const s = this._hass.states[c.comfort];
    const word = s && !["unavailable", "unknown", "none"].includes(s.state) ? s.state : null;
    const [color] = word ? TONES[word] || [INACTIVE] : [INACTIVE];
    const reason = word ? this._reason(word) : "";
    const notes = [];
    if (c.approx) notes.push("Temperature comes from a motion sensor and updates in coarse steps.");
    if (!c.humidity) notes.push("No humidity sensor in this room, so no dew point or comfort check on moisture.");
    const body = ov.querySelector(".crc-body");
    body.innerHTML =
      `<div class="crc-sum" style="--c:${color}"><span class="crc-word">${esc(word || "Not reporting")}</span><div class="crc-rd">${this._reading(c.temperature, "mdi:thermometer", 1)}${this._reading(c.humidity, "mdi:water-percent", 0)}${this._reading(c.dew, "mdi:water-thermometer-outline", 1)}</div></div>` +
      `${reason ? `<div class="crc-why">${esc(reason)}</div>` : ""}` +
      `<div class="crc-tabs"><button data-h="24" class="${this._hours === 24 ? "on" : ""}">24 h</button><button data-h="168" class="${this._hours === 168 ? "on" : ""}">7 d</button></div><div class="crc-graph"></div>` +
      `${notes.map((n) => `<div class="crc-note">${esc(n)}</div>`).join("")}` +
      `<button class="crc-link">Sensor details</button>`;
    body.querySelectorAll(".crc-tabs button").forEach((b) =>
      b.addEventListener("click", () => {
        this._hours = Number(b.dataset.h);
        this._paintPopup();
      }),
    );
    body.querySelector(".crc-link").addEventListener("click", () => {
      this.dispatchEvent(new CustomEvent("hass-more-info", { detail: { entityId: c.temperature || c.comfort }, bubbles: true, composed: true }));
    });
    const entities = [c.temperature, c.humidity, c.dew].filter((e) => e && this._hass.states[e]);
    if (entities.length) {
      const helpers = await window.loadCardHelpers();
      const card = await helpers.createCardElement({ type: "history-graph", entities, hours_to_show: this._hours });
      card.hass = this._hass;
      const g = body.querySelector(".crc-graph");
      if (g) g.appendChild(card);
    }
  }
}

customElements.define("climate-room-card", ClimateRoomCard);
