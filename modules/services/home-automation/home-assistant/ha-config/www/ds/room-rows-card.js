import { tokens } from "./tokens.js?v=8";
import { primitives } from "./primitives.js?v=8";
import { drillOr, mount, num, rowButton, rows as own } from "./dom.js?v=8";

class RoomRowsCard extends HTMLElement {
  constructor() {
    super();
    mount(this, tokens, primitives, own).innerHTML = `<div class="tile"><div class="tile__label"></div><div class="rows"></div></div>`;
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
      parts.push(s === "on" ? "on" : s === "off" ? "off" : "unavailable");
    }
    const t = num(h.states[r.temperature]);
    if (t !== null) parts.push(t.toFixed(1) + "°");
    const hum = num(h.states[r.humidity]);
    if (hum !== null) parts.push(Math.round(hum) + "%");
    return parts.join(" · ");
  }

  _row(r, text) {
    const b = rowButton(r.name, text);
    b.addEventListener("click", () => r.detail && drillOr(this, r.detail, r.lights || r.temperature));
    return b;
  }
}

if (!customElements.get("room-rows-card")) {
  customElements.define("room-rows-card", RoomRowsCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "room-rows-card", name: "Room rows", description: "Dense room rows that open a detail." });
}
