import { tokens } from "./tokens.js?v=8";
import { primitives } from "./primitives.js?v=8";
import { drill, moreInfo, mount, num, rowButton, rows as own } from "./dom.js?v=8";

const withUnit = (s, v) => `${v}${s?.attributes?.unit_of_measurement ? " " + s.attributes.unit_of_measurement : ""}`;

class CostListCard extends HTMLElement {
  constructor() {
    super();
    mount(this, tokens, primitives, own).innerHTML = `<div class="tile"><div class="tile__label"></div><div class="rows"></div></div>`;
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
    const top = this._config.top ?? 5;
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

  _row(e, name, text) {
    const b = rowButton(name, text);
    b.addEventListener("click", () => {
      const cards = [{ type: "history-graph", hours_to_show: 168, entities: [e.entity] }];
      if (e.energy) cards.push({ type: "statistics-graph", chart_type: "bar", period: "day", stat_types: ["change"], entities: [e.energy] });
      cards.push({ type: "entities", entities: [e.entity, e.power, e.energy].filter(Boolean) });
      if (!drill(this, { type: "vertical-stack", cards })) moreInfo(this, e.entity);
    });
    return b;
  }

  _all(n) {
    const b = rowButton(`All ${n} devices`, "");
    b.addEventListener("click", () => drill(this, { type: "custom:cost-list-card", entities: this._config.entities, top: n, title: this._config.title }));
    return b;
  }
}

if (!customElements.get("cost-list-card")) {
  customElements.define("cost-list-card", CostListCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "cost-list-card", name: "Cost list", description: "Cost rows sorted descending with per-row drill-down." });
}
