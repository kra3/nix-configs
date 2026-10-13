// Washer and dryer tiles: state colour, elapsed time, live power, last cycle and an Emptied button; tapping a tile opens its power history.

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
        const label = key === "unknown" ? "Unknown" : status;
        const power = st(m.power);
        const watts = power && !isNaN(parseFloat(power.state)) ? `${Math.round(parseFloat(power.state))} W` : "–";
        const cycle = st(m.last_cycle);
        const cycles = (cycle && cycle.attributes && cycle.attributes.cycles) || [];
        const last = cycles[0];
        const lastEnd = cycle ? Date.parse(cycle.state) : NaN;
        const runOn = st(m.running);
        const runStart = runOn ? Date.parse(runOn.last_changed) - 30000 : NaN;
        let sub;
        if (key === "running") sub = isNaN(runStart) ? "Cycle in progress" : `For ${span(minutes(now - runStart))}`;
        else if (key === "done") sub = isNaN(lastEnd) ? "Finished, waiting to be emptied" : `Finished ${span(minutes(now - lastEnd))} ago`;
        else if (key === "idle") sub = isNaN(lastEnd) ? "No runs recorded yet" : `Last run ${span(minutes(now - lastEnd))} ago`;
        else sub = "Waiting for the plug to report";
        const extra = last && (key === "done" || key === "idle") ? `${last.minutes} min · ${num(last.kwh)} kWh · ${num(last.cost)} kr` : "";
        const flag = st(m.flag);
        const waiting = key === "done" && flag && flag.state === "on";
        const pending = waiting && this._pending[m.flag] && now - this._pending[m.flag] < PENDING_MS;
        const btn = waiting ? `<button class="btn" data-flag="${esc(m.flag)}"${pending ? " disabled" : ""}>${pending ? "Clearing…" : "Emptied"}</button>` : "";
        return `<div class="m ${key}" style="--c:${TONES[key]}" data-power="${esc(m.power || "")}" tabindex="0" role="button" aria-label="${esc(m.name)}, ${esc(label)}">
          <div class="ic"><ha-icon icon="${esc(m.icon || "mdi:washing-machine")}"></ha-icon></div>
          <div class="tx"><div class="lab">${esc(m.name)}</div><div class="val">${esc(label)}</div><div class="sub">${esc(sub)}</div>${extra ? `<div class="sub">${esc(extra)}</div>` : ""}</div>
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

customElements.define("laundry-machine-card", LaundryMachineCard);
customElements.define("plug-cost-card", PlugCostCard);
window.customCards = window.customCards || [];
window.customCards.push({ type: "laundry-machine-card", name: "Laundry machines", description: "Washer and dryer state, elapsed time, power and last cycle" });
window.customCards.push({ type: "plug-cost-card", name: "Plug cost", description: "Estimated cost per plug: this month, today, week, quarter and last month" });
