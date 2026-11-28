import { sheet, tokens } from "./tokens.js?v=13";
import { primitives } from "./primitives.js?v=13";
import { drillOr, mount, num, rowButton, rows as own } from "./dom.js?v=13";

const extra = sheet(`
.row__v { display: flex; align-items: center; justify-content: flex-end; flex-wrap: wrap; gap: var(--ds-space-1) var(--ds-space-3); }
.val { display: inline-flex; align-items: center; gap: var(--ds-space-1); font-variant-numeric: tabular-nums; }
.val ha-icon { --mdc-icon-size: 16px; color: var(--secondary-text-color); }
.val.on ha-icon { color: var(--state-light-active-color, var(--warning-color)); }
`);

class RoomRowsCard extends HTMLElement {
  constructor() {
    super();
    mount(this, tokens, primitives, own, extra).innerHTML = `<div class="tile"><div class="tile__label"></div><div class="rows"></div></div>`;
  }

  setConfig(c) {
    if (!Array.isArray(c?.rooms)) throw new Error("room-rows-card: rooms is required");
    this._config = c;
    this.shadowRoot.querySelector(".tile__label").textContent = c.title || "";
    this.shadowRoot.querySelector(".tile__label").hidden = !c.title;
    this._key = null;
  }

  getCardSize() { return this._config?.rooms.length || 1; }
  getGridOptions() { return { columns: "full", min_columns: 3 }; }

  set hass(h) {
    const uid = h.user?.id;
    const quiet = (r) => !this._config.quiet || !(h.states[r.presence]?.state === "on" || h.states[r.lights]?.state === "on" || (r.also && h.states[r.also.entity]?.state === r.also.state) || r.pin_users?.includes(uid));
    const rows = this._config.rooms.filter(quiet).map((r) => ({ r, text: this._text(h, r) }));
    this.hidden = rows.length === 0;
    const key = JSON.stringify(rows.map((x) => [x.r.name, x.text]));
    if (key === this._key) return;
    this._key = key;
    this.shadowRoot.querySelector(".rows").replaceChildren(...rows.map(({ r, text }) => this._row(r, text)));
  }

  _text(h, r) {
    const parts = [];
    if (r.lights) {
      const s = h.states[r.lights]?.state;
      parts.push(s === "on" ? ["mdi:lightbulb-on", "on", "Lights on", "on"] : s === "off" ? ["mdi:lightbulb-outline", "off", "Lights off"] : ["mdi:lightbulb-question-outline", "unavailable", "Lights unavailable"]);
    }
    const t = num(h.states[r.temperature]);
    if (t !== null) parts.push(["mdi:thermometer", t.toFixed(1) + "°", "Temperature"]);
    const hum = num(h.states[r.humidity]);
    if (hum !== null) parts.push(["mdi:water-percent", Math.round(hum) + "%", "Humidity"]);
    return parts;
  }

  _row(r, parts) {
    const b = rowButton(r.name, "");
    b.setAttribute("aria-label", [r.name, ...parts.map(([, v, l]) => (l.startsWith("Lights") ? l : `${l} ${v}`))].join(", "));
    b.lastChild.replaceChildren(...parts.map(([icon, v, , cls]) => {
      const e = document.createElement("span");
      e.className = "val " + (cls || "");
      const i = document.createElement("ha-icon");
      i.setAttribute("icon", icon);
      i.setAttribute("aria-hidden", "true");
      e.append(i, v);
      return e;
    }));
    b.addEventListener("click", () => r.detail && drillOr(this, r.detail, r.lights || r.temperature));
    return b;
  }
}

if (!customElements.get("room-rows-card")) {
  customElements.define("room-rows-card", RoomRowsCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "room-rows-card", name: "Room rows", description: "Dense room rows that open a detail." });
}
