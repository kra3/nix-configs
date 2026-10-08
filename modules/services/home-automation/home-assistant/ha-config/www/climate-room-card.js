// Room climate tile: a status-tinted icon with a badge when the room is off its comfort range, the room name, the comfort word and temperature, humidity and dew point readings with glyphs.

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
      this.shadowRoot.querySelector("ha-card").addEventListener("click", () => {
        const entityId = c.temperature || c.comfort;
        this.dispatchEvent(new CustomEvent("hass-more-info", { detail: { entityId }, bubbles: true, composed: true }));
      });
    }
  }
}

customElements.define("climate-room-card", ClimateRoomCard);
