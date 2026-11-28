import { sheet, tokens } from "./tokens.js?v=5";
import { primitives } from "./primitives.js?v=5";

const own = sheet(`
:host { display: block; }
:host([hidden]) { display: none; }
.tile { padding-block: var(--ds-space-3); }
.tile__label { margin-bottom: var(--ds-space-1); }
button.row { width: 100%; box-sizing: border-box; min-height: var(--ds-touch); align-items: center; background: none; color: inherit; font: inherit;
  text-align: left; cursor: pointer; border: 0; border-top: 1px solid var(--divider-color); touch-action: manipulation; }
button.row:first-of-type { border-top: 0; }
button.row:focus-visible { outline: 2px solid var(--primary-color); outline-offset: -2px; border-radius: var(--ds-space-2); }
.row__v { text-align: right; overflow-wrap: anywhere; }
`);

const num = (s) => (s && s.state !== "" && Number.isFinite(Number(s.state)) ? Number(s.state) : null);

class RoomRowsCard extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" }).adoptedStyleSheets = [tokens, primitives, own];
    this.shadowRoot.innerHTML = `<div class="tile"><div class="tile__label"></div><div class="rows"></div></div>`;
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
    const b = document.createElement("button");
    b.className = "row";
    b.innerHTML = `<span class="row__k"></span><span class="row__v"></span>`;
    b.firstChild.textContent = r.name;
    b.lastChild.textContent = text;
    b.setAttribute("aria-label", [r.name, text].filter(Boolean).join(" · "));
    b.addEventListener("click", () => {
      if (!r.detail) return;
      const ev = new CustomEvent("ll-custom", { detail: { action: "fire-dom-event", cc_detail: r.detail }, bubbles: true, composed: true, cancelable: true });
      this.dispatchEvent(ev);
      const entityId = r.lights || r.temperature;
      if (!ev.defaultPrevented && entityId) this.dispatchEvent(new CustomEvent("hass-more-info", { detail: { entityId }, bubbles: true, composed: true }));
    });
    return b;
  }
}

if (!customElements.get("room-rows-card")) {
  customElements.define("room-rows-card", RoomRowsCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "room-rows-card", name: "Room rows", description: "Dense room rows that open a detail." });
}
