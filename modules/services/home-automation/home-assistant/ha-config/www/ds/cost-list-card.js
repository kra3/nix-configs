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
const withUnit = (s, v) => `${v}${s?.attributes?.unit_of_measurement ? " " + s.attributes.unit_of_measurement : ""}`;

class CostListCard extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" }).adoptedStyleSheets = [tokens, primitives, own];
    this.shadowRoot.innerHTML = `<div class="tile"><div class="tile__label"></div><div class="rows"></div></div>`;
  }

  setConfig(c) {
    if (!Array.isArray(c?.entities)) throw new Error("cost-list-card: entities is required");
    this._config = c;
    this.shadowRoot.querySelector(".tile__label").textContent = c.title || "";
    this.shadowRoot.querySelector(".tile__label").hidden = !c.title;
    this._key = null;
  }

  getCardSize() { return Math.min(this._config?.entities.length || 1, (this._config?.top ?? 5) + 1); }
  getGridOptions() { return { columns: "full", min_columns: 3 }; }

  set hass(h) {
    const top = this._expanded ? Infinity : this._config.top ?? 5;
    this._h = h;
    const rows = this._config.entities
      .map((e, i) => ({ e, i, s: h.states[e.entity], v: num(h.states[e.entity]) }))
      .sort((a, b) => (b.v ?? -Infinity) - (a.v ?? -Infinity) || a.i - b.i);
    const shown = rows.slice(0, top).map((r) => ({
      e: r.e,
      name: r.e.name || r.s?.attributes?.friendly_name || r.e.entity,
      text: this._text(h, r),
    }));
    const key = JSON.stringify([shown, rows.length]);
    if (key === this._key) return;
    this._key = key;
    const out = shown.map(({ e, name, text }) => this._row(e, name, text));
    if (rows.length > top) out.push(this._all(rows.length));
    this.shadowRoot.querySelector(".rows").replaceChildren(...out);
  }

  _text(h, { e, v, s }) {
    const parts = [v === null ? "—" : withUnit(s, v.toFixed(2))];
    const p = e.power && h.states[e.power];
    if (num(p) !== null) parts.push(withUnit(p, Number(p.state).toFixed(0)));
    return parts.join(" · ");
  }

  _btn(name, text) {
    const b = document.createElement("button");
    b.className = "row";
    b.innerHTML = `<span class="row__k"></span><span class="row__v"></span>`;
    b.firstChild.textContent = name;
    b.lastChild.textContent = text;
    b.setAttribute("aria-label", [name, text].filter(Boolean).join(" · "));
    return b;
  }

  _fire(detail) {
    return this.dispatchEvent(new CustomEvent("ll-custom", { detail: { action: "fire-dom-event", cc_detail: detail }, bubbles: true, composed: true, cancelable: true }));
  }

  _row(e, name, text) {
    const b = this._btn(name, text);
    b.addEventListener("click", () => {
      const cards = [{ type: "history-graph", hours_to_show: 168, entities: [e.entity] }];
      if (e.energy) cards.push({ type: "statistics-graph", chart_type: "bar", period: "day", stat_types: ["change"], entities: [e.energy] });
      cards.push({ type: "entities", entities: [e.entity, e.power, e.energy].filter(Boolean) });
      if (this._fire({ type: "vertical-stack", cards })) {
        this.dispatchEvent(new CustomEvent("hass-more-info", { detail: { entityId: e.entity }, bubbles: true, composed: true }));
      }
    });
    return b;
  }

  _all(n) {
    const b = this._btn(`All ${n} devices`, "");
    b.addEventListener("click", () => {
      if (!this._fire({ type: "custom:cost-list-card", entities: this._config.entities, top: 999, title: this._config.title })) return;
      this._expanded = true;
      this.hass = this._h;
    });
    return b;
  }
}

if (!customElements.get("cost-list-card")) {
  customElements.define("cost-list-card", CostListCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "cost-list-card", name: "Cost list", description: "Cost rows sorted descending with per-row drill-down." });
}
