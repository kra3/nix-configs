import { sheet, tokens } from "./tokens.js?v=15";
import { primitives } from "./primitives.js?v=15";
import { moreInfo, mount, rowButton, rows as own } from "./dom.js?v=15";
import { areaRows } from "./areas.js?v=15";

const extra = sheet(`
.sec + .sec { margin-top: var(--ds-space-3); }
.ctl { display: flex; align-items: center; border-top: 1px solid var(--divider-color); }
.tile__label + .ctl { border-top: 0; }
.ctl .row { flex: 1; min-width: 0; border-top: 0; }
.ctl .chip { min-width: 56px; justify-content: center; margin-left: var(--ds-space-2); border: 0; cursor: pointer; min-height: var(--ds-touch); touch-action: manipulation; }
.ctl .chip[aria-pressed=true] { background: color-mix(in srgb, var(--state-light-active-color, var(--warning-color)) 28%, var(--card-background-color)); }
`);

const listOf = (v) => (Array.isArray(v) ? v : String(v || "").split(","));

class AreaRoomCard extends HTMLElement {
  constructor() {
    super();
    mount(this, tokens, primitives, own, extra).innerHTML = `<div class="tile"></div>`;
  }

  setConfig(c) {
    this._config = c || {};
    if (!this._config.area) this.hidden = true;
    this._key = null;
  }

  getCardSize() { return 3; }
  getGridOptions() { return { columns: "full", min_columns: 3 }; }

  set hass(h) {
    const c = this._config;
    if (!c.area) return;
    const exclude = [...listOf(c.explicit), ...listOf(c.exclude)].map((x) => x.trim()).filter(Boolean);
    const { controls: ctl, openings: open, sensors: sens } = areaRows(h, c.area, exclude);
    this._h = h;
    const key = JSON.stringify([ctl, sens, open, ctl.map((x) => h.states[x.id].state)]);
    this.hidden = !ctl.length && !sens.length && !open.length;
    if (key === this._key) return;
    this._key = key;
    const area = h.areas?.[c.area]?.name || "";
    const sec = (title, kids) => {
      const d = document.createElement("div");
      d.className = "sec";
      const l = document.createElement("div");
      l.className = "tile__label";
      l.textContent = title;
      d.append(l, ...kids);
      return d;
    };
    const secs = [];
    if (ctl.length) secs.push(sec(c.title || (area ? `Also in ${area}` : "Also here"), ctl.map((x) => this._ctl(x))));
    if (open.length) secs.push(sec("Doors and windows", open.map((x) => this._info(x.id, x.name, x.text))));
    if (sens.length) secs.push(sec("Sensors", sens.map((x) => this._info(x.id, x.name, x.text))));
    this.shadowRoot.querySelector(".tile").replaceChildren(...secs);
  }

  _info(id, n, v) {
    const b = rowButton(n, v);
    b.addEventListener("click", () => moreInfo(this, id));
    return b;
  }

  _ctl({ id, name, text, toggle, readonly }) {
    if (readonly) {
      const d = document.createElement("div");
      d.className = "row";
      d.innerHTML = `<span class="row__k"></span><span class="row__v"></span>`;
      d.firstChild.textContent = name;
      d.lastChild.textContent = text;
      return d;
    }
    const wrap = document.createElement("div");
    wrap.className = "ctl";
    wrap.append(this._info(id, name, text));
    if (toggle) {
      const on = this._h.states[id].state;
      const t = document.createElement("button");
      t.className = "chip";
      const lit = on === "on" || on === "open" || on === "opening";
      t.setAttribute("aria-pressed", String(lit));
      t.setAttribute("aria-label", `Toggle ${name}`);
      t.textContent = toggle === "cover" ? (lit ? "Open" : "Closed") : lit ? "On" : "Off";
      t.addEventListener("click", () => this._h.callService(toggle, "toggle", { entity_id: id }));
      wrap.append(t);
    }
    return wrap;
  }
}

if (!customElements.get("area-room-card")) {
  customElements.define("area-room-card", AreaRoomCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "area-room-card", name: "Area room", description: "Devices assigned to an HA area, listed without per-device YAML." });
}
