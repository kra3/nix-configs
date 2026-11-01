// Next public-transport trip as a tile; tap for all trips, legs, Check and settings.

let TZ;
const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const hhmm = (d) => new Intl.DateTimeFormat("en-GB", { timeZone: TZ, hour: "2-digit", minute: "2-digit" }).format(d);
const wallNow = () => {
  const f = new Intl.DateTimeFormat("en-CA", { timeZone: TZ, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" });
  const p = Object.fromEntries(f.formatToParts(new Date()).map((x) => [x.type, +x.value]));
  return Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
};
const minsTo = (dep) => Math.floor((Date.parse(`${dep.replace(" ", "T")}:00Z`) - wallNow()) / 60000);
const transit = (t) => t.legs.filter((l) => l.n !== undefined);
const num = (l) => (/\d/.test(l.n) ? esc(l.n) : "");
const TONE = { "mdi:bus": "--teal-color", "mdi:train": "--purple-color", "mdi:tram": "--orange-color", "mdi:subway-variant": "--blue-color", "mdi:ferry": "--light-blue-color" };
const tone = (l) => `--tone: var(${TONE[l.i] || "--primary-color"})`;
const chip = (text, cls) => `<span class="chip ${cls || ""}">${text}</span>`;
const lines = (t) =>
  transit(t)
    .map((l) => `<span class="ln" style="${tone(l)}"><ha-icon icon="${esc(l.i)}"></ha-icon>${num(l)}</span>`)
    .join('<span class="sep">›</span>');
const pos = (l) => (l.pos ? `${l.i === "mdi:train" ? "spår" : "läge"} ${esc(l.pos)}` : "");
const live = (l, quiet) =>
  l.cancel ? chip("cancelled", "bad") : l.delay > 0 ? chip(`+${l.delay} min`, "warn") : l.rt && !quiet ? chip("on time", "good") : "";
const countdown = (t) => {
  if (transit(t).some((l) => l.cancel)) return chip("cancelled", "bad");
  const m = minsTo(t.dep);
  return chip(m <= 0 ? "now" : `in ${m} min`, m < 5 ? "warn" : m <= 15 ? "soon" : "");
};
const tripKey = (t) => t.dep + transit(t).map((l) => l.n).join("-");
const short = (o) => o.replace(/^Up to /, "").replace(/^At most /, "≤ ").replace(/ and trams$/, "");
const metres = (o) => parseFloat(o.match(/[\d.]+/)[0]) * (/km/.test(o) ? 1000 : 1);
const ordered = (opts) => (opts.every((o) => /\d/.test(o)) ? [...opts].sort((a, b) => metres(a) - metres(b)) : opts);

const CHIP_CSS = `
  .chip { --tone: var(--secondary-text-color); display: inline-flex; align-items: center; padding: 2px 10px; border-radius: 999px; font-size: 13px; font-weight: 600; white-space: nowrap; color: var(--tone); background: color-mix(in srgb, var(--tone) 16%, transparent); }
  .chip.soon { --tone: var(--primary-color); }
  .chip.warn { --tone: var(--warning-color, #ffa600); }
  .chip.bad { --tone: var(--error-color, #db4437); }
  .chip.good { --tone: var(--success-color, #43a047); }
  .ln { --tone: var(--primary-color); display: inline-flex; align-items: center; gap: 2px; padding: 0 6px; border-radius: 6px; font-size: 13px; font-weight: 700; line-height: 20px; color: var(--tone); background: color-mix(in srgb, var(--tone) 18%, transparent); }
  .ln ha-icon { --mdc-icon-size: 15px; }
  .sep { color: var(--secondary-text-color); padding: 0 3px; }
`;

const STYLE = `
  :host { display: block; }
  ha-card { cursor: pointer; }
  .tile { display: flex; align-items: center; gap: 12px; padding: 12px 14px; min-height: 44px; }
  .icon { --mdc-icon-size: 24px; color: var(--tone, var(--primary-color)); flex: none; }
  .txt { flex: 1; min-width: 0; }
  .title { font-size: 15px; font-weight: 600; color: var(--primary-text-color); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .sub { margin-top: 2px; font-size: 13px; line-height: 22px; color: var(--secondary-text-color); }
  .route { white-space: nowrap; }
  .sub .chip { padding: 0 8px; font-size: 12px; }
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
  .trip.next { box-shadow: inset 3px 0 var(--primary-color); }
  .sum { width: 100%; display: grid; grid-template-columns: 1fr auto; align-items: center; gap: 4px 10px; padding: 10px 4px 10px 10px; min-height: 44px; text-align: left; }
  .sum .t { font-size: 16px; font-weight: 700; font-variant-numeric: tabular-nums; }
  .sum .dur { margin-left: 6px; font-size: 13px; font-weight: 500; color: var(--secondary-text-color); }
  .sum .rt { grid-column: 1 / -1; }
  .legs { padding: 0 4px 12px 10px; display: grid; gap: 10px; font-size: 14px; }
  .leg { display: flex; gap: 10px; align-items: flex-start; }
  .leg > ha-icon { --mdc-icon-size: 20px; color: var(--tone, var(--secondary-text-color)); flex: none; }
  .leg.walk { color: var(--secondary-text-color); }
  .leg .lt { font-weight: 700; font-variant-numeric: tabular-nums; }
  .leg .meta { color: var(--secondary-text-color); }
  .leg .to { color: var(--secondary-text-color); font-size: 13px; margin-top: 2px; }
  .set { margin-top: 8px; border-top: 1px solid var(--divider-color); padding: 8px 4px 0; display: grid; gap: 8px; }
  .row { display: grid; grid-template-columns: 104px 1fr; align-items: center; gap: 8px; }
  .set-h { font-size: 13px; font-weight: 700; }
  .set-h span { display: block; font-size: 12px; font-weight: 400; color: var(--secondary-text-color); }
  .lbl { font-size: 13px; color: var(--secondary-text-color); }
  .opts { display: flex; flex-wrap: wrap; gap: 6px; }
  .opt { min-height: 34px; padding: 0 12px; border-radius: 999px; font-size: 13px; font-weight: 600; color: var(--secondary-text-color); background: color-mix(in srgb, var(--secondary-text-color) 12%, transparent); }
  .opt.on { color: var(--primary-color); background: color-mix(in srgb, var(--primary-color) 18%, transparent); }
  ${CHIP_CSS}
`;

class TripCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.entity || !config.person) throw new Error("trip-card: entity and person are required");
    this._config = { hide_slower: "input_boolean.transit_hide_slower", settings: [], ...config };
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
    TZ = hass.config?.time_zone;
    this._render();
  }

  _here() {
    const s = this._hass.states[this._config.person]?.state;
    return s === "home" ? "Home" : s && !["not_home", "unknown", "unavailable"].includes(s) ? s : "Here";
  }

  _event() {
    const now = wallNow();
    const today = new Date(now).toISOString().slice(0, 10);
    return (this._config.calendars || [])
      .map((e) => this._hass.states[e]?.attributes || {})
      .filter((a) => a.location && !a.all_day && a.start_time?.startsWith(today) && Date.parse(`${a.end_time.replace(" ", "T")}Z`) > now)
      .map((a) => ({ title: a.message, place: a.location, starts: a.start_time, key: `${a.message}|${a.start_time}` }))
      .sort((x, y) => x.starts.localeCompare(y.starts))[0];
  }

  _data() {
    const c = this._config;
    const ev = c.calendars && this._event();
    if (c.calendars && !ev) return { none: true };
    const s = this._hass.states[c.entity];
    if (!s || ["unknown", "unavailable"].includes(s.state)) return { ev, need: "Not checked yet" };
    const a = s.attributes;
    const all = (a.trips || []).filter((t) => minsTo(t.dep) >= 0);
    const best = all.filter((t) => t.best);
    const showAll = this._hass.states[c.hide_slower]?.state !== "on";
    const d = { a, ev, shown: showAll ? all : best, hidden: showAll ? 0 : all.length - best.length, updated: new Date(s.state) };
    d.hero = d.shown.find((t) => t.best) || d.shown[0];
    if (ev && a.event !== ev.key) d.need = "Not checked yet";
    else if (a.from_state !== this._hass.states[c.person]?.state) d.need = a.from_state ? `You're now at ${this._here()}` : "Not checked yet";
    else if (!a.ok) d.need = "No trips found";
    else if (!d.shown.length) d.need = "Those trips have left";
    return d;
  }

  _render() {
    if (!this._hass || !this._config) return;
    const d = this._data();
    if (!!d.none !== this.hidden) {
      this.hidden = !!d.none;
      this.dispatchEvent(new Event("card-visibility-changed", { bubbles: true, composed: true }));
    }
    if (d.none) return this._close();
    const h = !d.need && d.hero;
    let html;
    if (h) {
      const first = transit(h)[0] || {};
      const extra = [lines(h), pos(first), `→ ${esc(h.arr)}`, live(first, true)];
      html = `<ha-icon class="icon" style="${tone(first)}" icon="${esc(first.i || "mdi:train-bus")}"></ha-icon>
        <div class="txt"><div class="title">${esc(d.a.destination)} · Leave ${esc(h.dep.slice(11, 16))}</div>
        <div class="sub">${extra.filter(Boolean).map((x) => `<span class="route">${x}</span>`).join(" · ")}</div></div>${countdown(h)}`;
    } else {
      html = `<ha-icon class="icon" icon="${d.ev ? "mdi:calendar-clock" : "mdi:train-bus"}"></ha-icon>
        <div class="txt"><div class="title">${d.ev ? `${esc(d.ev.title)} · ${esc(d.ev.starts.slice(11, 16))}` : "Trips"}</div><div class="sub">${esc(d.need)} · tap to check</div></div>`;
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
    const ev = this._config.calendars && this._event();
    this._busy = true;
    this._render();
    try {
      await this._hass.callService("script", "transit_check", { person: this._config.person, ...(ev && { place: ev.place, title: ev.title, starts: ev.starts }) });
    } finally {
      this._busy = false;
      this._render();
    }
  }

  _settings() {
    const row = (label, pills) => `<div class="row"><span class="lbl">${esc(label)}</span><div class="opts">${pills.join("")}</div></div>`;
    const pill = (e, o, label, on) => `<button class="opt ${on ? "on" : ""}" data-e="${esc(e)}" data-o="${esc(o)}">${esc(label)}</button>`;
    const sa = this._hass.states[this._config.hide_slower];
    const rows = sa ? [row("Slower trips", [pill(sa.entity_id, "off", "Show", sa.state !== "on"), pill(sa.entity_id, "on", "Hide", sa.state === "on")])] : [];
    for (const e of this._config.settings) {
      const s = this._hass.states[e];
      if (s) rows.push(row(s.attributes.friendly_name || e, ordered(s.attributes.options || []).map((o) => pill(e, o, short(o), s.state === o))));
    }
    return `<div class="set"><div class="set-h">Search options<span>Changing one re-runs Check</span></div>${rows.join("")}</div>`;
  }

  _renderPopup(d) {
    if (!this._ov) return;
    const root = this._ov.shadowRoot;
    const a = d.a || {};
    const title = a.origin ? `${esc(a.origin)} → ${esc(a.destination)}` : "Trips";
    const sub = d.updated ? `${a.by ? `Arrive by ${esc(a.by.slice(11, 16))} · ` : ""}Updated ${hhmm(d.updated)}${d.hidden ? ` · ${d.hidden} slower hidden` : ""}` : "";
    const alert = d.need ? `<ha-alert alert-type="${a.ok === false ? "warning" : "info"}">${esc(d.need)}${a.ok === false ? ". Allow more walking or changes below." : ". Tap Check."}</ha-alert>` : "";
    const rows = (d.need ? [] : d.shown).map((t) => {
      const k = tripKey(t);
      const legs = t.legs
        .map((l) =>
          l.walk !== undefined
            ? `<div class="leg walk"><ha-icon icon="mdi:walk"></ha-icon><div>${esc(l.walk)} min walk</div></div>`
            : `<div class="leg" style="${tone(l)}"><ha-icon icon="${esc(l.i)}"></ha-icon><div><span class="lt">${esc(l.dep.slice(11, 16))}</span>
               <span class="ln" style="${tone(l)}">${esc(l.n)}</span> ${esc(l.from)} <span class="meta">${pos(l) ? `· ${pos(l)}` : ""}</span> ${live(l)}
               <div class="to">→ ${esc(l.arr)} ${esc(l.to)}</div></div></div>`,
        )
        .join("");
      return `<div class="trip ${t === d.hero ? "next" : ""}"><button class="sum" data-k="${esc(k)}" aria-expanded="${this._openKeys.has(k)}">
        <span class="t">${esc(t.dep.slice(11, 16))} → ${esc(t.arr)}<span class="dur">${esc(t.min)} min</span></span><span class="cd">${countdown(t)}</span>
        <span class="rt">${lines(t)}</span></button>
        ${this._openKeys.has(k) ? `<div class="legs">${legs}</div>` : ""}</div>`;
    });
    const html = `<div class="head"><div class="txt"><div class="title">${title}</div><div class="sub">${sub}</div></div>
      <button class="check ${this._busy ? "busy" : ""}"><ha-icon icon="mdi:refresh"></ha-icon>${this._busy ? "Checking" : "Check"}</button>
      <button class="x" aria-label="Close">×</button></div>${alert}<div class="list">${rows.join("")}</div>${this._settings()}`;
    if (html !== this._popHtml) {
      this._popHtml = html;
      root.querySelector(".body").innerHTML = html;
    }
  }

  _pick(e, o) {
    const [domain] = e.split(".");
    if (domain === "input_boolean") return this._hass.callService(domain, o === "on" ? "turn_on" : "turn_off", { entity_id: e });
    if (this._hass.states[e]?.state === o) return;
    this._hass.callService(domain, "select_option", { entity_id: e, option: o }).then(() => this._check());
  }

  _open() {
    if (this._ov) return;
    const d = this._data();
    this._openKeys = new Set(!d.need && d.hero ? [tripKey(d.hero)] : []);
    const ov = document.createElement("div");
    ov.attachShadow({ mode: "open" }).innerHTML = `<style>${POPUP_STYLE}</style>
      <div class="ov"><div class="sheet" role="dialog" aria-modal="true"><div class="body"></div></div></div>`;
    ov.shadowRoot.querySelector(".ov").addEventListener("click", (e) => {
      if (e.target.classList.contains("ov")) return this._close();
      const btn = e.composedPath().find((n) => n.tagName === "BUTTON");
      if (!btn) return;
      if (btn.classList.contains("x")) return this._close();
      if (btn.classList.contains("check")) return this._check();
      if (btn.dataset.e) return this._pick(btn.dataset.e, btn.dataset.o);
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
  }

  _close() {
    if (!this._ov) return;
    document.removeEventListener("keydown", this._onKey);
    this._ov.remove();
    this._ov = null;
  }
}

if (typeof customElements !== "undefined" && !customElements.get("trip-card")) {
  customElements.define("trip-card", TripCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "trip-card", name: "Trip card", description: "Next public-transport trip with a details popup." });
}
