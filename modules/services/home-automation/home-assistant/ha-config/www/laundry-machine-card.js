// Washer and dryer tiles (phase, finish estimate, live power, last cycle, Emptied button), care counters with a Done reset, and recent loads drawn as phase-coloured bars.

const STYLE = `
  :host { display: block; }
  ha-card { padding: 0; background: none; border: none; box-shadow: none; }
  .row { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 10px; }
  .m { display: flex; align-items: center; gap: 12px; padding: 12px 14px; border-radius: 12px; cursor: pointer; outline: none; min-width: 0;
       background: color-mix(in srgb, var(--c) 9%, transparent); border: 1px solid color-mix(in srgb, var(--c) 28%, transparent); }
  .m:focus-visible { box-shadow: 0 0 0 2px var(--c); }
  .ic { flex: none; width: 44px; height: 44px; border-radius: 50%; display: flex; align-items: center; justify-content: center;
        background: color-mix(in srgb, var(--c) 20%, transparent); color: var(--c); }
  .ic ha-icon { --mdc-icon-size: 26px; }
  .tx { flex: 1; min-width: 0; }
  .lab { font-size: 11px; font-weight: 700; letter-spacing: 0.6px; text-transform: uppercase; color: var(--secondary-text-color); }
  .val { font-size: 20px; font-weight: 700; line-height: 1.2; color: var(--primary-text-color); }
  .sub { font-size: 12px; line-height: 1.35; color: var(--secondary-text-color); overflow-wrap: anywhere; }
  .rt { flex: none; display: flex; flex-direction: column; align-items: flex-end; gap: 6px; }
  .w { font-size: 15px; font-weight: 600; color: var(--primary-text-color); font-variant-numeric: tabular-nums; }
  .btn { font: inherit; font-size: 13px; font-weight: 600; min-height: 44px; padding: 0 14px; border-radius: 10px; cursor: pointer;
         border: 1px solid var(--c); background: var(--c); color: var(--text-primary-color, #fff); }
  .btn[disabled] { opacity: 0.6; cursor: default; }
  .m.done .btn { color: #1a1a1a; }
  .m.idle .val, .m.unknown .val { color: var(--secondary-text-color); }
  .pg { height: 4px; border-radius: 2px; margin-top: 6px; background: color-mix(in srgb, var(--c) 18%, transparent); overflow: hidden; }
  .pg i { display: block; height: 100%; background: var(--c); }
  @media (prefers-reduced-motion: no-preference) {
    .m.running .ic { animation: pulse 2.4s ease-in-out infinite; }
    @keyframes pulse { 50% { opacity: 0.55; } }
  }
`;

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const TONES = {
  running: "var(--info-color, #039be5)",
  done: "var(--warning-color, #ffa600)",
  idle: "var(--state-inactive-color, #9e9e9e)",
  unknown: "var(--state-inactive-color, #9e9e9e)",
};
const PENDING_MS = 4000;

const minutes = (ms) => Math.max(0, Math.round(ms / 60000));
const span = (m) => {
  if (m < 1) return "under a minute";
  if (m < 60) return `${m} min`;
  if (m < 1440) return m % 60 ? `${Math.floor(m / 60)} h ${m % 60} min` : `${Math.floor(m / 60)} h`;
  return `${Math.floor(m / 1440)} d`;
};
const num = (v, d = 2) => (isNaN(parseFloat(v)) ? "–" : parseFloat(v).toFixed(d));
const median = (xs) => {
  const v = xs.filter((x) => x > 0).sort((a, b) => a - b);
  if (!v.length) return NaN;
  const h = Math.floor(v.length / 2);
  return v.length % 2 ? v[h] : (v[h - 1] + v[h]) / 2;
};
const clock = (ms) => new Date(ms).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", hourCycle: "h23" });

class LaundryMachineCard extends HTMLElement {
  setConfig(config) {
    if (!config || !Array.isArray(config.machines) || !config.machines.length) throw new Error("laundry-machine-card: machines are required");
    this._config = config;
    this._pending = this._pending || {};
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      const open = (el) => {
        if (el && el.dataset.power) this.dispatchEvent(new CustomEvent("hass-more-info", { detail: { entityId: el.dataset.power }, bubbles: true, composed: true }));
      };
      this.shadowRoot.addEventListener("click", (e) => {
        const btn = e.target.closest("button[data-flag]");
        if (btn) {
          e.stopPropagation();
          if (!this._hass || btn.disabled) return;
          this._pending[btn.dataset.flag] = Date.now();
          this._hass.callService("input_boolean", "turn_off", { entity_id: btn.dataset.flag });
          this._render();
          setTimeout(() => this._render(), PENDING_MS + 100);
          return;
        }
        open(e.target.closest(".m"));
      });
      this.shadowRoot.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          const el = e.target.closest && e.target.closest(".m");
          if (el && e.target === el) {
            e.preventDefault();
            open(el);
          }
        }
      });
    }
  }

  connectedCallback() {
    this._timer = setInterval(() => this._render(), 30000);
  }

  disconnectedCallback() {
    clearInterval(this._timer);
  }

  getCardSize() {
    return 3;
  }

  set hass(hass) {
    this._hass = hass;
    this._render();
  }

  _render() {
    if (!this._config || !this._hass) return;
    const hass = this._hass;
    const now = Date.now();
    const st = (id) => (id ? hass.states[id] : undefined);
    const cells = this._config.machines
      .map((m) => {
        const status = (st(m.status) && st(m.status).state) || "Unknown";
        const key = ["running", "done", "idle"].includes(status.toLowerCase()) ? status.toLowerCase() : "unknown";
        let label = key === "unknown" ? "Unknown" : status;
        const power = st(m.power);
        const watts = power && !isNaN(parseFloat(power.state)) ? `${Math.round(parseFloat(power.state))} W` : "–";
        const cycle = st(m.last_cycle);
        const cycles = (cycle && cycle.attributes && cycle.attributes.cycles) || [];
        const last = cycles[0];
        const lastEnd = cycle ? Date.parse(cycle.state) : NaN;
        const runOn = st(m.running);
        const runStart = runOn ? Date.parse(runOn.last_changed) - 30000 : NaN;
        const phase = st(m.phase);
        const phaseName = phase && !["Off", "unknown", "unavailable"].includes(phase.state) ? phase.state : "";
        const typical = cycles.length >= 2 ? median(cycles.map((c) => c.minutes)) : NaN;
        const elapsed = minutes(now - runStart);
        let sub;
        let bar = "";
        if (key === "running" && !isNaN(runStart) && !isNaN(typical)) {
          sub = elapsed < typical ? `Done about ${clock(runStart + typical * 60000)} · ${span(elapsed)} in` : `${span(elapsed)} in, longer than usual`;
          bar = `<div class="pg"><i style="width:${Math.min(100, (elapsed / typical) * 100).toFixed(0)}%"></i></div>`;
        } else if (key === "running") sub = isNaN(runStart) ? "Cycle in progress" : `For ${span(elapsed)}`;
        else if (key === "done") sub = isNaN(lastEnd) ? "Finished, waiting to be emptied" : `Finished ${span(minutes(now - lastEnd))} ago`;
        else if (key === "idle") sub = isNaN(lastEnd) ? "No runs recorded yet" : `Last run ${span(minutes(now - lastEnd))} ago`;
        else sub = "Waiting for the plug to report";
        const extra = last && (key === "done" || key === "idle") ? `${last.minutes} min · ${num(last.kwh)} kWh · ${num(last.cost)} kr` : "";
        if (key === "running" && phaseName) label = phaseName === "Stopped" ? "Stopping" : phaseName;
        const flag = st(m.flag);
        const waiting = key === "done" && flag && flag.state === "on";
        const pending = waiting && this._pending[m.flag] && now - this._pending[m.flag] < PENDING_MS;
        const btn = waiting ? `<button class="btn" data-flag="${esc(m.flag)}"${pending ? " disabled" : ""}>${pending ? "Clearing…" : "Emptied"}</button>` : "";
        return `<div class="m ${key}" style="--c:${TONES[key]}" data-power="${esc(m.power || "")}" tabindex="0" role="button" aria-label="${esc(m.name)}, ${esc(label)}">
          <div class="ic"><ha-icon icon="${esc(m.icon || "mdi:washing-machine")}"></ha-icon></div>
          <div class="tx"><div class="lab">${esc(m.name)}</div><div class="val">${esc(label)}</div><div class="sub">${esc(sub)}</div>${extra ? `<div class="sub">${esc(extra)}</div>` : ""}${bar}</div>
          <div class="rt"><div class="w">${esc(watts)}</div>${btn}</div>
        </div>`;
      })
      .join("");
    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card><div class="row">${cells}</div></ha-card>`;
  }
}

const COST_STYLE = `
  :host { display: block; }
  ha-card { padding: 10px; }
  .row { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 10px; }
  .d { padding: 12px 14px; border-radius: 12px; min-width: 0; background: var(--secondary-background-color); }
  .top { display: flex; align-items: center; gap: 10px; }
  .top ha-icon { --mdc-icon-size: 22px; color: var(--c); flex: none; }
  .lab { font-size: 11px; font-weight: 700; letter-spacing: 0.6px; text-transform: uppercase; color: var(--secondary-text-color); flex: 1; }
  .hero { font-size: 22px; font-weight: 700; color: var(--primary-text-color); font-variant-numeric: tabular-nums; }
  .hero small { font-size: 12px; font-weight: 500; color: var(--secondary-text-color); margin-left: 4px; }
  .grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 6px; margin-top: 10px; }
  .k { min-width: 0; }
  .k .t { font-size: 10px; font-weight: 700; letter-spacing: 0.4px; text-transform: uppercase; color: var(--secondary-text-color); }
  .k .v { font-size: 14px; font-weight: 600; color: var(--primary-text-color); font-variant-numeric: tabular-nums; }
  .foot { margin: 10px 4px 2px; font-size: 12px; line-height: 1.4; color: var(--secondary-text-color); }
`;

class PlugCostCard extends HTMLElement {
  setConfig(config) {
    if (!config || !Array.isArray(config.devices) || !config.devices.length) throw new Error("plug-cost-card: devices are required");
    this._config = config;
    if (!this.shadowRoot) this.attachShadow({ mode: "open" });
  }

  getCardSize() {
    return 3;
  }

  set hass(hass) {
    this._hass = hass;
    this._render();
  }

  _render() {
    if (!this._config || !this._hass) return;
    const hass = this._hass;
    const cells = this._config.devices
      .map((d) => {
        const s = hass.states[d.entity];
        const a = (s && s.attributes) || {};
        const k = (t, v) => `<div class="k"><div class="t">${t}</div><div class="v">${esc(num(v))}</div></div>`;
        return `<div class="d" style="--c:${esc(d.color || "var(--primary-color)")}"><div class="top"><ha-icon icon="${esc(d.icon || "mdi:flash")}"></ha-icon><div class="lab">${esc(d.name)}</div>
          <div class="hero">${esc(num(s && s.state))}<small>kr this month</small></div></div>
          <div class="grid">${k("Today", a.today)}${k("Week", a.week)}${k("Quarter", a.quarter)}${k("Last month", a.last_month)}</div></div>`;
      })
      .join("");
    const price = this._config.price && this._hass.states[this._config.price];
    const foot = `${price ? `Price now ${num(price.state)} kr/kWh with VAT. ` : ""}Estimated from this month's average spot; E.ON sets the final price after the month ends.`;
    this.shadowRoot.innerHTML = `<style>${COST_STYLE}</style><ha-card><div class="row">${cells}</div><div class="foot">${esc(foot)}</div></ha-card>`;
  }
}

const CARE_STYLE = `
  :host { display: block; }
  ha-card { padding: 4px 14px; }
  .r { display: flex; align-items: center; gap: 12px; padding: 10px 0; border-top: 1px solid var(--divider-color); }
  .r:first-child { border-top: none; }
  .ic { flex: none; width: 40px; height: 40px; border-radius: 50%; display: grid; place-items: center;
        background: color-mix(in srgb, var(--c) 18%, transparent); color: var(--c); }
  .ic ha-icon { --mdc-icon-size: 22px; }
  .tx { flex: 1; min-width: 0; }
  .n { font-size: 14px; font-weight: 600; color: var(--primary-text-color); }
  .s { font-size: 12px; color: var(--secondary-text-color); margin-top: 2px; }
  .r.due .s { color: var(--c); font-weight: 600; }
  .pg { height: 6px; border-radius: 3px; margin-top: 6px; background: var(--secondary-background-color); overflow: hidden; }
  .pg i { display: block; height: 100%; border-radius: 3px; background: var(--c); }
  .btn { flex: none; font: inherit; font-size: 13px; font-weight: 600; min-height: 44px; padding: 0 14px; border-radius: 10px; cursor: pointer;
         border: 1px solid color-mix(in srgb, var(--c) 50%, transparent); background: none; color: var(--c); }
  .r.due .btn { background: var(--c); border-color: var(--c); color: var(--text-primary-color, #fff); }
  .btn[disabled] { opacity: 0.6; cursor: default; }
`;

class LaundryCareCard extends HTMLElement {
  setConfig(config) {
    if (!config || !Array.isArray(config.items) || !config.items.length) throw new Error("laundry-care-card: items are required");
    this._config = config;
    this._pending = this._pending || {};
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      this.shadowRoot.addEventListener("click", (e) => {
        const btn = e.target.closest("button[data-i]");
        if (!btn || btn.disabled || !this._hass) return;
        const item = this._config.items[+btn.dataset.i];
        if (!window.confirm(item.confirm || `${item.name} done? This resets the count.`)) return;
        this._pending[item.entity] = Date.now();
        this._hass.callService("counter", "reset", { entity_id: item.entity });
        this._render();
        setTimeout(() => this._render(), PENDING_MS + 100);
      });
    }
  }

  getCardSize() {
    return this._config ? this._config.items.length + 1 : 3;
  }

  set hass(hass) {
    this._hass = hass;
    this._render();
  }

  _render() {
    if (!this._config || !this._hass) return;
    const now = Date.now();
    const rows = this._config.items
      .map((item, i) => {
        const s = this._hass.states[item.entity];
        const n = s ? parseInt(s.state, 10) : NaN;
        const every = item.every || 10;
        const unit = item.unit || "cycles";
        const pending = this._pending[item.entity] && now - this._pending[item.entity] < PENDING_MS;
        let text;
        let due = false;
        if (isNaN(n)) text = "Count unavailable";
        else if (n >= every) {
          due = true;
          text = n > every ? `Due now · ${n - every} ${unit} overdue` : "Due now";
        } else text = `${n} of ${every} · ${every - n} ${unit} to go`;
        const tone = due ? "var(--warning-color, #ffa600)" : "var(--primary-color)";
        const pct = isNaN(n) ? 0 : Math.min(100, (n / every) * 100);
        return `<div class="r${due ? " due" : ""}" style="--c:${tone}">
          <div class="ic"><ha-icon icon="${esc(item.icon || "mdi:wrench-clock")}"></ha-icon></div>
          <div class="tx"><div class="n">${esc(item.name)}</div><div class="s">${esc(text)}</div><div class="pg"><i style="width:${pct.toFixed(0)}%"></i></div></div>
          <button class="btn" data-i="${i}"${pending || isNaN(n) ? " disabled" : ""} aria-label="${esc(item.name)} done">${pending ? "Resetting…" : "Done"}</button>
        </div>`;
      })
      .join("");
    this.shadowRoot.innerHTML = `<style>${CARE_STYLE}</style><ha-card>${rows}</ha-card>`;
  }
}

const PHASE_COLORS = {
  Filling: "#4a7fb0",
  Heating: "#ff7b7b",
  Washing: "#6ab7ff",
  Rinsing: "#9fd4ff",
  Spinning: "#c9a7e8",
  Starting: "#c79a6b",
  Drying: "#ffb06b",
  Finishing: "#ffd08f",
  Cooling: "#8fd3c7",
  Stopped: "#8a8a8a",
  "Anti-crease": "#b9a37e",
};
const MACHINE_COLORS = { washer: "#6ab7ff", dryer: "#ffb06b" };
const hatch = (c) => `repeating-linear-gradient(135deg, ${c} 0 6px, color-mix(in srgb, ${c} 45%, transparent) 6px 12px)`;
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const DAY = 86400000;
const GAP_DRAW_MAX = 60;

const startMs = (c, now) => {
  if (c.ts) return c.ts * 1000;
  const m = /(\d{1,2}) (\w{3}) (\d{1,2}):(\d{2})/.exec(c.start || "");
  if (!m) return NaN;
  const d = new Date(new Date(now).getFullYear(), MONTHS.indexOf(m[2]), +m[1], +m[3], +m[4]);
  if (d.getTime() > now + DAY) d.setFullYear(d.getFullYear() - 1);
  return d.getTime();
};

const RUNS_STYLE = `
  :host { display: block; }
  ha-card { padding: 4px 14px 12px; }
  .load { padding: 10px 0; border-top: 1px solid var(--divider-color); }
  .load:first-child { border-top: none; }
  .day { font-size: 13px; font-weight: 600; color: var(--primary-text-color); margin-bottom: 6px; }
  .track { position: relative; height: 22px; }
  .seg { position: absolute; top: 0; height: 22px; border-radius: 6px; display: flex; overflow: hidden; }
  .seg i { display: block; height: 100%; }
  .gap { position: absolute; top: 10px; border-top: 2px dashed var(--secondary-text-color); }
  .gap span { position: absolute; left: 0; right: 0; top: -17px; text-align: center; font-size: 11px; color: var(--secondary-text-color); white-space: nowrap; }
  .meta { display: flex; flex-wrap: wrap; column-gap: 12px; row-gap: 2px; margin-top: 6px; font-size: 12px; color: var(--secondary-text-color); font-variant-numeric: tabular-nums; }
  .meta b { color: var(--primary-text-color); font-weight: 600; }
  .meta b.off { color: var(--warning-color, #ffa600); }
  .legend { display: flex; flex-wrap: wrap; gap: 4px 12px; padding-top: 10px; border-top: 1px solid var(--divider-color); font-size: 11px; color: var(--secondary-text-color); }
  .legend { flex-direction: column; }
  .lg { display: flex; flex-wrap: wrap; gap: 4px 12px; }
  .lg b { font-weight: 600; color: var(--primary-text-color); min-width: 52px; }
  .legend span.nd::before { background: var(--h); }
  .legend span::before { content: ""; display: inline-block; width: 9px; height: 9px; border-radius: 2px; background: var(--c); margin-right: 4px; vertical-align: -1px; }
  .empty { padding: 14px 0; font-size: 13px; color: var(--secondary-text-color); }
`;

class LaundryRunsCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.washer || !config.dryer) throw new Error("laundry-runs-card: washer and dryer are required");
    this._config = config;
    if (!this.shadowRoot) this.attachShadow({ mode: "open" });
  }

  getCardSize() {
    return 5;
  }

  set hass(hass) {
    const sig = [this._config.washer, this._config.dryer].map((e) => hass.states[e] && hass.states[e].last_updated).join();
    this._hass = hass;
    if (sig === this._sig) return;
    this._sig = sig;
    this._render();
  }

  _runs(machine) {
    const s = this._hass.states[this._config[machine]];
    const now = Date.now();
    return ((s && s.attributes.cycles) || [])
      .map((c) => ({ ...c, machine, at: startMs(c, now), minutes: +c.minutes || 0 }))
      .filter((r) => !isNaN(r.at));
  }

  _render() {
    if (!this._config || !this._hass) return;
    const washes = this._runs("washer").sort((a, b) => a.at - b.at);
    const dries = this._runs("dryer").sort((a, b) => a.at - b.at);
    const typical = { washer: washes.length >= 3 ? median(washes.map((r) => r.minutes)) : NaN, dryer: dries.length >= 3 ? median(dries.map((r) => r.minutes)) : NaN };
    const loads = washes.map((w) => ({ wash: w }));
    for (const d of dries) {
      const end = (r) => r.at + r.minutes * 60000;
      const host = loads
        .filter((l) => !l.dry && end(l.wash) <= d.at + 60000 && d.at - end(l.wash) <= DAY && !washes.some((w) => w.at > l.wash.at && w.at < d.at))
        .pop();
      if (host) host.dry = d;
      else loads.push({ dry: d });
    }
    const shown = loads.sort((a, b) => (b.wash || b.dry).at - (a.wash || a.dry).at).slice(0, this._config.loads || 6);
    if (!shown.length) {
      this.shadowRoot.innerHTML = `<style>${RUNS_STYLE}</style><ha-card><div class="empty">No runs recorded yet.</div></ha-card>`;
      return;
    }
    const gapOf = (l) => (l.wash && l.dry ? Math.max(0, Math.round((l.dry.at - l.wash.at) / 60000 - l.wash.minutes)) : 0);
    const drawn = (l) => (l.wash ? l.wash.minutes : 0) + (l.dry ? l.dry.minutes : 0) + Math.min(gapOf(l), GAP_DRAW_MAX) + (l.wash && l.dry ? 4 : 0);
    const scale = Math.max(150, ...shown.map(drawn));
    const pct = (m) => ((m / scale) * 100).toFixed(2);
    const used = new Set();
    const bar = (r, left) => {
      const ph = (r.phases || []).filter((p) => p[1] > 0);
      const total = ph.reduce((a, p) => a + p[1], 0);
      const inner = total
        ? ph
            .map((p) => {
              used.add(p[0]);
              return `<i style="width:${((p[1] / total) * 100).toFixed(2)}%;background:${PHASE_COLORS[p[0]] || MACHINE_COLORS[r.machine]}" title="${esc(p[0])} ${Math.round(p[1])} min"></i>`;
            })
            .join("")
        : "";
      if (!total) used.add(`${r.machine}:none`);
      return `<div class="seg" style="left:${pct(left)}%;width:${pct(r.minutes)}%;${total ? "" : `background:${hatch(MACHINE_COLORS[r.machine])}`}">${inner}</div>`;
    };
    const meta = (r) => {
      const t = typical[r.machine];
      const off = !isNaN(t) && (r.minutes > t * 1.3 || r.minutes < t * 0.7);
      const name = r.machine === "washer" ? "Wash" : "Dry";
      return `<span>${name} ${esc(clock(r.at))} · <b${off ? ' class="off"' : ""}>${r.minutes} min</b> · <b>${num(r.kwh)} kWh</b> · <b>${num(r.cost)} kr</b></span>`;
    };
    const rows = shown
      .map((l) => {
        const first = l.wash || l.dry;
        const day = new Date(first.at).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" });
        let track = "";
        let x = 0;
        if (l.wash) {
          track += bar(l.wash, 0);
          x = l.wash.minutes;
        }
        if (l.wash && l.dry) {
          const g = gapOf(l);
          const w = Math.min(g, GAP_DRAW_MAX);
          track += `<div class="gap" style="left:${pct(x + 2)}%;width:${pct(w)}%"><span>⌛ ${esc(span(g))}</span></div>`;
          x += w + 4;
        }
        if (l.dry) track += bar(l.dry, x);
        return `<div class="load"><div class="day">${esc(day)}</div><div class="track">${track}</div><div class="meta">${l.wash ? meta(l.wash) : ""}${l.dry ? meta(l.dry) : ""}</div></div>`;
      })
      .join("");
    const groups = [
      ["Washer", "washer", ["Filling", "Heating", "Washing", "Rinsing", "Spinning"]],
      ["Dryer", "dryer", ["Starting", "Drying", "Finishing", "Cooling", "Anti-crease", "Stopped"]],
    ];
    const legend = groups
      .map(([label, machine, phases]) => {
        const items = phases.filter((k) => used.has(k)).map((k) => `<span style="--c:${PHASE_COLORS[k]}">${esc(k)}</span>`);
        if (used.has(`${machine}:none`)) items.push(`<span style="--c:${MACHINE_COLORS[machine]};--h:${hatch(MACHINE_COLORS[machine])}" class="nd">No phase data</span>`);
        return items.length ? `<div class="lg"><b>${label}</b>${items.join("")}</div>` : "";
      })
      .join("");
    this.shadowRoot.innerHTML = `<style>${RUNS_STYLE}</style><ha-card>${rows}<div class="legend">${legend}</div></ha-card>`;
  }
}

customElements.define("laundry-machine-card", LaundryMachineCard);
customElements.define("plug-cost-card", PlugCostCard);
customElements.define("laundry-care-card", LaundryCareCard);
customElements.define("laundry-runs-card", LaundryRunsCard);
window.customCards = window.customCards || [];
window.customCards.push({ type: "laundry-machine-card", name: "Laundry machines", description: "Washer and dryer state, elapsed time, power and last cycle" });
window.customCards.push({ type: "laundry-care-card", name: "Laundry care", description: "Cycles since each care task, with progress to due and a Done reset" });
window.customCards.push({ type: "laundry-runs-card", name: "Laundry runs", description: "Recent loads as phase-coloured wash and dry bars with the wait between" });
window.customCards.push({ type: "plug-cost-card", name: "Plug cost", description: "Estimated cost per plug: this month, today, week, quarter and last month" });
