// Next public-transport trip as a tile; tap for all trips, legs, Check and settings.

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const hhmm = (d) => `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
const minsTo = (dep) => Math.floor((new Date(dep.replace(" ", "T")) - Date.now()) / 60000);
const transit = (t) => t.legs.filter((l) => l.n !== undefined);
const chip = (text, tone) => `<span class="chip ${tone || ""}">${text}</span>`;
const lines = (t) =>
  transit(t)
    .map((l) => `<span class="ln"><ha-icon icon="${esc(l.i)}"></ha-icon>${esc(l.n)}</span>`)
    .join('<span class="sep">›</span>');
const pos = (l) => (l.pos ? `${l.i === "mdi:train" ? "spår" : "läge"} ${esc(l.pos)}` : "");
const live = (l, quiet) =>
  l.cancel ? chip("cancelled", "bad") : l.delay > 0 ? chip(`+${l.delay} min`, "warn") : l.rt && !quiet ? chip("on time", "good") : "";
const countdown = (t) => {
  if (transit(t).some((l) => l.cancel)) return chip("cancelled", "bad");
  const m = minsTo(t.dep);
  return chip(m <= 0 ? "now" : `in ${m} min`, m < 5 ? "warn" : "");
};
const tripKey = (t) => t.dep + transit(t).map((l) => l.n).join("-");

const CHIP_CSS = `
  .chip { --tone: var(--secondary-text-color); display: inline-flex; align-items: center; padding: 2px 10px; border-radius: 999px; font-size: 13px; font-weight: 600; white-space: nowrap; color: var(--tone); background: color-mix(in srgb, var(--tone) 16%, transparent); }
  .chip.warn { --tone: var(--warning-color, #ffa600); }
  .chip.bad { --tone: var(--error-color, #db4437); }
  .chip.good { --tone: var(--success-color, #43a047); }
  .ln { display: inline-flex; align-items: center; gap: 2px; font-weight: 600; }
  .ln ha-icon { --mdc-icon-size: 16px; color: var(--secondary-text-color); }
  .sep { color: var(--secondary-text-color); padding: 0 4px; }
`;

const STYLE = `
  :host { display: block; }
  ha-card { cursor: pointer; }
  .tile { display: flex; align-items: center; gap: 12px; padding: 12px 14px; min-height: 44px; }
  .icon { --mdc-icon-size: 24px; color: var(--primary-color); flex: none; }
  .txt { flex: 1; min-width: 0; }
  .title { font-size: 15px; font-weight: 600; color: var(--primary-text-color); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .sub { display: flex; flex-wrap: wrap; align-items: center; gap: 2px 8px; margin-top: 2px; font-size: 13px; color: var(--secondary-text-color); }
  ${CHIP_CSS}
`;

const POPUP_STYLE = `
  .ov { position: fixed; inset: 0; z-index: 9; background: rgba(0, 0, 0, 0.6); display: flex; align-items: center; justify-content: center; padding: 16px; }
  .sheet { width: min(560px, 100%); max-height: 90vh; overflow: auto; background: var(--card-background-color, #1c1c1c); color: var(--primary-text-color); border-radius: var(--ha-card-border-radius, 16px); padding: 12px 12px 16px; box-sizing: border-box; }
  .head { display: flex; align-items: flex-start; gap: 8px; }
  .head .txt { flex: 1; min-width: 0; padding-left: 4px; }
  .title { font-size: 16px; font-weight: 600; }
  .sub { font-size: 12px; color: var(--secondary-text-color); margin-top: 2px; }
  button { font: inherit; color: inherit; background: none; border: 0; cursor: pointer; }
  .check { display: inline-flex; align-items: center; gap: 4px; min-height: 36px; padding: 0 12px; border-radius: 999px; font-size: 13px; font-weight: 600; color: var(--primary-color); background: color-mix(in srgb, var(--primary-color) 14%, transparent); }
  .check ha-icon { --mdc-icon-size: 18px; }
  .check.busy ha-icon { animation: spin 1s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .x { font-size: 26px; line-height: 1; padding: 4px 8px; color: var(--secondary-text-color); }
  ha-alert { display: block; margin-top: 10px; }
  .list { margin-top: 10px; }
  .trip { border-top: 1px solid var(--divider-color); }
  .sum { width: 100%; display: flex; flex-wrap: wrap; align-items: center; gap: 4px 10px; padding: 10px 4px; min-height: 44px; text-align: left; }
  .sum .t { font-weight: 600; font-variant-numeric: tabular-nums; }
  .sum .dur { color: var(--secondary-text-color); font-size: 13px; }
  .sum .cd { margin-left: auto; }
  .legs { padding: 0 4px 12px; display: grid; gap: 8px; font-size: 14px; }
  .leg { display: flex; gap: 10px; align-items: flex-start; }
  .leg > ha-icon { --mdc-icon-size: 20px; color: var(--secondary-text-color); flex: none; }
  .leg .meta { color: var(--secondary-text-color); }
  .leg .to { color: var(--secondary-text-color); font-size: 13px; }
  .set { margin-top: 8px; border-top: 1px solid var(--divider-color); padding-top: 8px; }
  .set-h { font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.6px; color: var(--secondary-text-color); padding: 4px 4px 0; }
  .set ha-card { box-shadow: none; border: 0; background: none; }
  ${CHIP_CSS}
`;

class TripCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.entity || !config.person) throw new Error("trip-card: entity and person are required");
    this._config = { show_all: "input_boolean.transit_show_all", settings: [], ...config };
    this._html = "";
    if (!this.shadowRoot) this.attachShadow({ mode: "open" });
  }

  getCardSize() {
    return 1;
  }

  getGridOptions() {
    return { columns: 12, min_columns: 6 };
  }

  connectedCallback() {
    this._tick = setInterval(() => this._render(), 30000);
  }

  disconnectedCallback() {
    clearInterval(this._tick);
    this._close();
  }

  set hass(hass) {
    this._hass = hass;
    if (this._settingsCard) this._settingsCard.hass = hass;
    this._render();
  }

  _here() {
    const s = this._hass.states[this._config.person]?.state;
    return s === "home" ? "Home" : s && !["not_home", "unknown", "unavailable"].includes(s) ? s : "Here";
  }

  _data() {
    const c = this._config;
    const s = this._hass.states[c.entity];
    if (!s || ["unknown", "unavailable"].includes(s.state)) return { need: "No trips checked yet" };
    const a = s.attributes;
    const all = (a.trips || []).filter((t) => minsTo(t.dep) >= 0);
    const best = all.filter((t) => t.best);
    const showAll = this._hass.states[c.show_all]?.state === "on";
    const d = { a, shown: showAll ? all : best, hidden: showAll ? 0 : all.length - best.length, updated: new Date(s.state) };
    d.age = (Date.now() - d.updated) / 60000;
    if (a.origin !== this._here()) d.need = `You're now at ${this._here()}`;
    else if (!a.ok) d.need = "No trips found";
    else if (!d.shown.length) d.need = "Those trips have left";
    return d;
  }

  _render() {
    if (!this._hass || !this._config) return;
    const d = this._data();
    const h = !d.need && d.shown[0];
    let html;
    if (h) {
      const first = transit(h)[0] || {};
      const extra = [lines(h), pos(first), `arrive ${esc(h.arr)}`, live(first, true), d.age > 15 ? `updated ${hhmm(d.updated)}` : ""];
      html = `<ha-icon class="icon" icon="${esc(first.i || "mdi:train-bus")}"></ha-icon>
        <div class="txt"><div class="title">${esc(d.a.destination)} · Leave ${esc(h.dep.slice(11, 16))}</div>
        <div class="sub">${extra.filter(Boolean).join(" · ")}</div></div>${countdown(h)}`;
    } else {
      html = `<ha-icon class="icon" icon="mdi:train-bus"></ha-icon>
        <div class="txt"><div class="title">Trips</div><div class="sub">${esc(d.need)} · tap to check</div></div>`;
    }
    if (html !== this._html) {
      this._html = html;
      this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card><div class="tile" role="button" tabindex="0">${html}</div></ha-card>`;
      const open = () => {
        this._open();
        if (this._data().need) this._check();
      };
      const tile = this.shadowRoot.querySelector(".tile");
      tile.addEventListener("click", open);
      tile.addEventListener("keydown", (e) => (e.key === "Enter" || e.key === " ") && open());
    }
    this._renderPopup(d);
  }

  async _check() {
    if (this._busy) return;
    this._busy = true;
    this._render();
    try {
      await this._hass.callService("script", "transit_check", { person: this._config.person });
    } finally {
      this._busy = false;
      this._render();
    }
  }

  _renderPopup(d) {
    if (!this._ov) return;
    const root = this._ov.shadowRoot;
    const a = d.a || {};
    const title = a.origin ? `${esc(a.origin)} → ${esc(a.destination)}` : "Trips";
    const sub = d.updated ? `Updated ${hhmm(d.updated)}${d.hidden ? ` · ${d.hidden} slower hidden` : ""}` : "";
    const alert = d.need ? `<ha-alert alert-type="${a.ok === false ? "warning" : "info"}">${esc(d.need)}${a.ok === false ? ". Allow more walking or changes below." : ". Tap Check."}</ha-alert>` : "";
    const rows = (d.need ? [] : d.shown).map((t) => {
      const k = tripKey(t);
      const legs = t.legs
        .map((l) =>
          l.walk !== undefined
            ? `<div class="leg"><ha-icon icon="mdi:walk"></ha-icon><div>${esc(l.walk)} min walk</div></div>`
            : `<div class="leg"><ha-icon icon="${esc(l.i)}"></ha-icon><div><b>${esc(l.n)}</b> ${esc(l.dep.slice(11, 16))} ${esc(l.from)}
               <span class="meta">${pos(l) ? `· ${pos(l)}` : ""}</span> ${live(l)}<div class="to">→ ${esc(l.arr)} ${esc(l.to)}</div></div></div>`,
        )
        .join("");
      return `<div class="trip"><button class="sum" data-k="${esc(k)}" aria-expanded="${this._openKeys.has(k)}">
        <span class="t">${esc(t.dep.slice(11, 16))} → ${esc(t.arr)}</span><span class="dur">${esc(t.min)} min</span>
        <span>${lines(t)}</span><span class="cd">${countdown(t)}</span></button>
        ${this._openKeys.has(k) ? `<div class="legs">${legs}</div>` : ""}</div>`;
    });
    const html = `<div class="head"><div class="txt"><div class="title">${title}</div><div class="sub">${sub}</div></div>
      <button class="check ${this._busy ? "busy" : ""}"><ha-icon icon="mdi:refresh"></ha-icon>${this._busy ? "Checking" : "Check"}</button>
      <button class="x" aria-label="Close">×</button></div>${alert}<div class="list">${rows.join("")}</div>`;
    if (html !== this._popHtml) {
      this._popHtml = html;
      root.querySelector(".body").innerHTML = html;
    }
  }

  async _open() {
    if (this._ov) return;
    const d = this._data();
    this._openKeys = new Set(!d.need && d.shown[0] ? [tripKey(d.shown[0])] : []);
    const ov = document.createElement("div");
    ov.attachShadow({ mode: "open" }).innerHTML = `<style>${POPUP_STYLE}</style>
      <div class="ov"><div class="sheet" role="dialog" aria-modal="true"><div class="body"></div>
      <div class="set"><div class="set-h">Settings</div><div class="slot"></div></div></div></div>`;
    const root = ov.shadowRoot;
    root.querySelector(".ov").addEventListener("click", (e) => {
      if (e.target.classList.contains("ov")) return this._close();
      const btn = e.composedPath().find((n) => n.tagName === "BUTTON");
      if (!btn) return;
      if (btn.classList.contains("x")) return this._close();
      if (btn.classList.contains("check")) return this._check();
      const k = btn.dataset.k;
      if (k) {
        this._openKeys.has(k) ? this._openKeys.delete(k) : this._openKeys.add(k);
        this._renderPopup(this._data());
      }
    });
    this._onKey = (e) => e.key === "Escape" && this._close();
    document.addEventListener("keydown", this._onKey);
    document.body.appendChild(ov);
    this._ov = ov;
    this._popHtml = "";
    this._renderPopup(d);
    const entities = [this._config.show_all, ...this._config.settings];
    const helpers = await window.loadCardHelpers();
    const card = await helpers.createCardElement({ type: "entities", entities });
    card.hass = this._hass;
    if (this._ov !== ov) return;
    this._settingsCard = card;
    root.querySelector(".slot").appendChild(card);
  }

  _close() {
    if (!this._ov) return;
    document.removeEventListener("keydown", this._onKey);
    this._ov.remove();
    this._ov = null;
    this._settingsCard = null;
  }
}

if (typeof customElements !== "undefined" && !customElements.get("trip-card")) {
  customElements.define("trip-card", TripCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "trip-card", name: "Trip card", description: "Next public-transport trip with a details popup." });
}
