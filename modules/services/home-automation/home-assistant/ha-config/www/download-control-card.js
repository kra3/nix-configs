// Compact download client control: one pause/resume toggle and a speed-limit slider.

const STYLE = `
  :host { display: block; }
  ha-card { padding: 12px 16px; }
  .row { display: flex; align-items: center; gap: 16px; }
  .pill { display: inline-flex; align-items: center; gap: 8px; padding: 8px 14px 8px 10px; border: 0; border-radius: 999px; cursor: pointer; font: inherit; font-size: 14px; font-weight: 600; white-space: nowrap; color: var(--c); background: color-mix(in srgb, var(--c) 16%, transparent); }
  .pill:disabled { opacity: 0.5; cursor: default; }
  .pill ha-icon { --mdc-icon-size: 20px; }
  .limit { flex: 1; min-width: 0; display: flex; align-items: center; gap: 12px; }
  .lab { font-size: 11px; font-weight: 700; letter-spacing: 0.6px; text-transform: uppercase; color: var(--secondary-text-color); }
  .val { min-width: 4ch; text-align: right; font-size: 14px; font-weight: 600; font-variant-numeric: tabular-nums; color: var(--primary-text-color); }
  input[type="range"] { flex: 1; min-width: 60px; accent-color: var(--c); }
`;

class DownloadControlCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.switch || !config.number) throw new Error("download-control-card: switch and number are required");
    this._config = config;
    if (!this.shadowRoot) this.attachShadow({ mode: "open" });
    this._built = false;
  }

  getCardSize() {
    return 1;
  }

  set hass(hass) {
    this._hass = hass;
    this._render();
  }

  _build() {
    const c = this._config;
    this.shadowRoot.innerHTML =
      `<style>${STYLE}</style><ha-card style="--c:${c.color || "var(--primary-color)"}"><div class="row">` +
      `<button class="pill" type="button"><ha-icon></ha-icon><span></span></button>` +
      `<div class="limit"><span class="lab">${c.limit_label || "Limit"}</span><input type="range"><span class="val"></span></div>` +
      `</div></ha-card>`;
    const root = this.shadowRoot;
    this._pill = root.querySelector(".pill");
    this._icon = root.querySelector("ha-icon");
    this._text = root.querySelector(".pill span");
    this._range = root.querySelector("input");
    this._val = root.querySelector(".val");
    this._pill.addEventListener("click", () => {
      const s = this._hass.states[this._config.switch];
      if (!s) return;
      this._hass.callService("switch", s.state === "on" ? "turn_off" : "turn_on", { entity_id: this._config.switch });
    });
    this._range.addEventListener("input", () => {
      this._drag = true;
      this._val.textContent = this._range.value + (this._unit || "");
    });
    this._range.addEventListener("change", () => {
      this._drag = false;
      this._hass.callService("number", "set_value", { entity_id: this._config.number, value: Number(this._range.value) });
    });
    this._built = true;
  }

  _render() {
    if (!this._config || !this._hass) return;
    if (!this._built) this._build();
    const sw = this._hass.states[this._config.switch];
    const num = this._hass.states[this._config.number];
    const usable = (s) => s && s.state !== "unavailable" && s.state !== "unknown";
    const running = usable(sw) && sw.state === "on";
    this._pill.disabled = !usable(sw);
    this._icon.setAttribute("icon", running ? this._config.running_icon || "mdi:download" : this._config.paused_icon || "mdi:pause");
    this._text.textContent = !usable(sw) ? "Unavailable" : running ? this._config.running_label || "Downloading" : this._config.paused_label || "Paused";
    this._range.disabled = !usable(num);
    if (!usable(num)) return;
    const a = num.attributes;
    this._unit = a.unit_of_measurement ? " " + a.unit_of_measurement : "";
    this._range.min = a.min !== undefined ? a.min : 0;
    this._range.max = a.max !== undefined ? a.max : 100;
    this._range.step = a.step !== undefined ? a.step : 1;
    if (!this._drag) {
      this._range.value = num.state;
      this._val.textContent = Math.round(Number(num.state)) + this._unit;
    }
  }
}

customElements.define("download-control-card", DownloadControlCard);
