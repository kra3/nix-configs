// Compact download client control: one pause/resume toggle and a speed-limit slider.

import { sheet, tokens } from "./ds/tokens.js?v=11";
import { primitives } from "./ds/primitives.js?v=11";
import { mount } from "./ds/dom.js?v=11";

const own = sheet(`
:host { display: block; }
.ctl { display: flex; flex-wrap: wrap; align-items: center; gap: var(--ds-space-2) var(--ds-space-4); }
button.chip { min-height: var(--ds-touch); padding: 0 var(--ds-space-4) 0 var(--ds-space-3); gap: var(--ds-space-2); border: 0; cursor: pointer;
  font: var(--ds-title); white-space: nowrap; touch-action: manipulation; }
button.chip:disabled { opacity: 0.5; cursor: default; }
button.chip ha-icon { --mdc-icon-size: 20px; }
.limit { flex: 1 1 200px; min-width: 0; display: flex; align-items: center; gap: var(--ds-space-3); }
.val { min-width: 4ch; text-align: right; font: var(--ds-title); font-variant-numeric: tabular-nums; }
input[type="range"] { flex: 1; min-width: 60px; min-height: var(--ds-touch); accent-color: var(--tint); }
`);

class DownloadControlCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.switch || !config.number) throw new Error("download-control-card: switch and number are required");
    this._config = config;
    if (!this.shadowRoot) mount(this, tokens, primitives, own);
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
      `<div class="tile" style="--tint:${c.color || "var(--primary-color)"}"><div class="ctl">` +
      `<button class="chip chip--tint" type="button"><ha-icon></ha-icon><span></span></button>` +
      `<div class="limit"><span class="tile__label">${c.limit_label || "Limit"}</span><input type="range"><span class="val"></span></div>` +
      `</div></div>`;
    const root = this.shadowRoot;
    this._pill = root.querySelector(".chip");
    this._icon = root.querySelector("ha-icon");
    this._text = root.querySelector(".chip span");
    this._range = root.querySelector("input");
    this._val = root.querySelector(".val");
    this._pill.addEventListener("click", () => {
      const s = this._hass.states[this._config.switch];
      if (!s || this._pending) return;
      const want = s.state !== "on";
      this._pending = { want, until: Date.now() + 10000 };
      this._hass.callService("switch", want ? "turn_on" : "turn_off", { entity_id: this._config.switch });
      this._render();
      setTimeout(() => this._render(), 10100);
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
    let running = usable(sw) && sw.state === "on";
    if (this._pending && (running === this._pending.want || Date.now() > this._pending.until)) this._pending = null;
    if (this._pending) running = this._pending.want;
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
