// Comfort range: a draggable Low/High range on a temperature scale with the season's guideline band underneath, a night-offset stepper, a humidity-vs-ceiling bar and collapsible `advanced` rows (name, effect, optional `now` Jinja line, -/+ steppers; `when: {entity, state | state_not}` shows a row or stepper conditionally).

const STYLE = `
  :host { display: block; }
  ha-card { padding: 12px 16px 8px; }
  .range { font-size: 24px; font-weight: 600; font-variant-numeric: tabular-nums; color: var(--primary-text-color); }
  .sub { font-size: 12px; color: var(--secondary-text-color); margin-top: 2px; }
  .sub b { font-weight: 600; color: var(--primary-text-color); }
  .warn { color: var(--warning-color, #ffa600); }
  .top { display: flex; align-items: flex-start; justify-content: space-between; gap: 8px; }
  .chip { font-size: 11px; font-weight: 700; letter-spacing: 0.6px; text-transform: uppercase; padding: 2px 8px; border-radius: 10px; background: var(--secondary-background-color); color: var(--secondary-text-color); }
  .scale { position: relative; height: 100px; margin: 10px 14px 0; touch-action: none; user-select: none; }
  .bar { position: absolute; left: 0; right: 0; top: 32px; height: 8px; border-radius: 4px; overflow: hidden; background: linear-gradient(90deg, var(--info-color, #039be5), var(--success-color, #43a047) 50%, var(--warning-color, #ffa600)); }
  .dim { position: absolute; top: 0; bottom: 0; background: color-mix(in srgb, var(--card-background-color, #1c1c1c) 78%, transparent); }
  .hd { position: absolute; top: 22px; width: 28px; height: 28px; margin-left: -14px; border-radius: 50%; background: var(--card-background-color, #fff); border: 3px solid var(--primary-text-color); box-sizing: border-box; cursor: grab; touch-action: none; outline: none; }
  .hd:focus-visible { box-shadow: 0 0 0 3px var(--primary-color); }
  .hd:active { cursor: grabbing; }
  .hl { position: absolute; top: 0; margin-left: -20px; width: 40px; text-align: center; font-size: 13px; font-weight: 700; font-variant-numeric: tabular-nums; color: var(--primary-text-color); }
  .gl { position: absolute; left: 0; right: 0; top: 56px; height: 14px; background: linear-gradient(90deg, var(--info-color, #039be5), var(--success-color, #43a047) 50%, var(--warning-color, #ffa600)); }
  .glt { position: absolute; top: 56px; height: 14px; font-size: 9px; font-weight: 700; line-height: 14px; text-align: center; text-transform: uppercase; letter-spacing: 0.5px; color: var(--card-background-color, #1c1c1c); overflow: hidden; white-space: nowrap; }
  .tk { position: absolute; top: 76px; margin-left: -12px; width: 24px; text-align: center; font-size: 10px; color: var(--secondary-text-color); font-variant-numeric: tabular-nums; }
  .line { display: flex; flex-wrap: wrap; align-items: center; gap: 8px 16px; padding: 10px 0; border-top: 1px solid var(--divider-color); }
  .txt { flex: 1 1 200px; min-width: 0; }
  .name { font-size: 14px; font-weight: 600; color: var(--primary-text-color); }
  .eff { font-size: 12px; line-height: 1.35; color: var(--secondary-text-color); margin-top: 2px; }
  .now { font-size: 12px; line-height: 1.35; color: var(--primary-color); margin-top: 2px; }
  .ctl { display: flex; gap: 12px; flex: none; margin-left: auto; }
  .st { display: flex; align-items: center; gap: 4px; }
  .v { min-width: 56px; text-align: center; font-size: 15px; font-weight: 600; font-variant-numeric: tabular-nums; color: var(--primary-text-color); }
  .v.dead { color: var(--secondary-text-color); font-weight: 400; }
  button.b { width: 36px; height: 36px; border: none; border-radius: 50%; background: var(--secondary-background-color); color: var(--primary-text-color); cursor: pointer; display: grid; place-items: center; padding: 0; }
  button.b:hover:not(:disabled) { background: var(--divider-color); }
  button.b:disabled { opacity: 0.35; cursor: default; }
  button.b ha-icon { --mdc-icon-size: 18px; }
  .htrack { position: relative; height: 6px; border-radius: 3px; background: var(--secondary-background-color); margin: 8px 0 4px; }
  .hfill { position: absolute; left: 0; top: 0; bottom: 0; border-radius: 3px; background: var(--c); }
  .hcap { position: absolute; top: -4px; bottom: -4px; width: 3px; margin-left: -1px; background: var(--primary-text-color); border-radius: 2px; }
  button.adv { display: flex; align-items: center; gap: 4px; width: 100%; border: none; background: none; color: var(--secondary-text-color); font-size: 13px; font-weight: 600; padding: 10px 0 6px; cursor: pointer; border-top: 1px solid var(--divider-color); }
  button.adv ha-icon { --mdc-icon-size: 18px; }
`;

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const PEND_MS = 3000;
const num = (v) => (v === undefined || v === null || v === "" || isNaN(Number(v)) ? null : Number(v));
const fmt = (v) => String(Math.round(v * 100) / 100);

class ComfortCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.low || !config.high) throw new Error("comfort-card: low and high are required");
    this._config = config;
    this._now = {};
    this._pend = {};
    this._open = false;
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      const root = this.shadowRoot;
      root.addEventListener("click", (e) => {
        if (e.target.closest("button.adv")) {
          this._open = !this._open;
          this._render();
          return;
        }
        const b = e.target.closest("button.b");
        if (!b || !this._hass) return;
        this._step(b.dataset.e, Number(b.dataset.d));
      });
      root.addEventListener("pointerdown", (e) => this._down(e));
      root.addEventListener("pointermove", (e) => this._move(e));
      root.addEventListener("pointerup", (e) => this._up(e));
      root.addEventListener("pointercancel", (e) => this._up(e));
      root.addEventListener("keydown", (e) => {
        const h = e.target.closest && e.target.closest(".hd");
        if (!h || (e.key !== "ArrowLeft" && e.key !== "ArrowRight")) return;
        e.preventDefault();
        this._step(h.dataset.e, e.key === "ArrowRight" ? 1 : -1);
      });
    }
  }

  getCardSize() {
    return 5;
  }

  connectedCallback() {
    if (this._hass) this._subscribe();
  }

  disconnectedCallback() {
    (this._unsubs || []).forEach((u) => u());
    this._unsubs = [];
    this._subbed = false;
  }

  set hass(hass) {
    this._hass = hass;
    if (!this._subbed && this.isConnected) this._subscribe();
    if (!this._drag) this._render();
  }

  _subscribe() {
    if (!this._config || !this._hass || !this._hass.connection) return;
    this._subbed = true;
    this._unsubs = [];
    (this._config.advanced || []).forEach((r, i) => {
      if (!r.now) return;
      this._hass.connection
        .subscribeMessage(
          (res) => {
            this._now[i] = res.result;
            if (!this._drag) this._render();
          },
          { type: "render_template", template: r.now, strict: false, report_errors: false },
        )
        .then((u) => this._unsubs.push(u))
        .catch(() => {});
    });
  }

  _state(id) {
    return id && this._hass ? this._hass.states[id] : undefined;
  }

  _val(id) {
    const s = this._state(id);
    if (!s) return null;
    const p = this._pend[id];
    const live = num(s.state);
    if (p && (p.v === live || Date.now() - p.t >= PEND_MS)) delete this._pend[id];
    return this._pend[id] ? this._pend[id].v : live;
  }

  _show(w) {
    if (!w) return true;
    const s = this._state(w.entity);
    const v = s && s.state;
    if (w.state !== undefined) return [].concat(w.state).includes(v);
    if (w.state_not !== undefined) return ![].concat(w.state_not).includes(v);
    return true;
  }

  _summer() {
    const s = this._state(this._config.season);
    return !!s && s.state === "summer";
  }

  _highId() {
    return this._summer() && this._config.high_summer ? this._config.high_summer : this._config.high;
  }

  _set(id, v) {
    this._pend[id] = { v, t: Date.now() };
    this._hass.callService("input_number", "set_value", { entity_id: id, value: v });
  }

  _step(id, dir) {
    const s = this._state(id);
    if (!s) return;
    const a = s.attributes;
    const step = Number(a.step) || 1;
    const base = this._val(id);
    if (base === null) return;
    const v = Math.min(Number(a.max), Math.max(Number(a.min), Math.round((base + dir * step) * 1000) / 1000));
    this._pend[id] = { v, t: Date.now() };
    this._hass.callService("input_number", dir > 0 ? "increment" : "decrement", { entity_id: id });
    this._render();
  }

  _scale() {
    const sc = this._config.scale || [14, 30];
    return [sc[0], sc[1]];
  }

  _down(e) {
    const h = e.target.closest && e.target.closest(".hd");
    if (!h || !this._hass) return;
    e.preventDefault();
    h.setPointerCapture(e.pointerId);
    this._drag = { id: h.dataset.e, kind: h.dataset.k, el: h, v: null };
  }

  _move(e) {
    const d = this._drag;
    if (!d) return;
    const track = this.shadowRoot.querySelector(".scale");
    const r = track.getBoundingClientRect();
    const [lo, hi] = this._scale();
    const a = this._state(d.id).attributes;
    const step = Number(a.step) || 1;
    let v = lo + Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)) * (hi - lo);
    v = Math.round(v / step) * step;
    const other = this._val(d.kind === "low" ? this._highId() : this._config.low);
    v = Math.min(Number(a.max), Math.max(Number(a.min), v));
    if (other !== null) v = d.kind === "low" ? Math.min(v, other - step) : Math.max(v, other + step);
    d.v = v;
    const l = d.kind === "low" ? v : this._val(this._config.low);
    const h = d.kind === "high" ? v : this._val(this._highId());
    const pct = (x) => ((Math.min(hi, Math.max(lo, x)) - lo) / (hi - lo)) * 100;
    d.el.style.left = `${pct(v)}%`;
    const q = (s) => this.shadowRoot.querySelector(s);
    q(".dl").style.width = `${pct(l)}%`;
    q(".dr").style.left = `${pct(h)}%`;
    const lab = q(`.hl[data-k="${d.kind}"]`);
    lab.style.left = `${pct(v)}%`;
    lab.textContent = fmt(v);
    const rng = this.shadowRoot.querySelector(".range");
    if (rng) rng.textContent = `${fmt(l)} – ${fmt(h)} °C`;
  }

  _up() {
    const d = this._drag;
    if (!d) return;
    this._drag = null;
    if (d.v !== null) this._set(d.id, d.v);
    this._render();
  }

  _stepper(it) {
    const id = it.entity;
    const s = this._state(id);
    const dead = !s || s.state === "unavailable" || s.state === "unknown";
    if (dead) return `<div class="st"><span class="v dead">Unavailable</span></div>`;
    const a = s.attributes;
    const v = this._val(id);
    const unit = a.unit_of_measurement ? ` ${a.unit_of_measurement}` : "";
    return (
      `<div class="st"><button class="b" data-e="${esc(id)}" data-d="-1" aria-label="Decrease"${v <= Number(a.min) ? " disabled" : ""}><ha-icon icon="mdi:minus"></ha-icon></button>` +
      `<span class="v">${esc(fmt(v))}${esc(unit)}</span>` +
      `<button class="b" data-e="${esc(id)}" data-d="1" aria-label="Increase"${v >= Number(a.max) ? " disabled" : ""}><ha-icon icon="mdi:plus"></ha-icon></button></div>`
    );
  }

  _row(r, now) {
    const ctl = r.entities.filter((it) => this._show(it.when)).map((it) => this._stepper(it)).join("");
    return (
      `<div class="line"><div class="txt"><div class="name">${esc(r.name || "")}</div>${r.effect ? `<div class="eff">${esc(r.effect)}</div>` : ""}${now ? `<div class="now">${esc(now)}</div>` : ""}</div>` +
      `<div class="ctl">${ctl}</div></div>`
    );
  }

  _bar() {
    const c = this._config;
    const [lo, hi] = this._scale();
    const pct = (v) => `${Math.min(100, Math.max(0, ((v - lo) / (hi - lo)) * 100))}%`;
    const low = this._val(c.low);
    const highId = this._highId();
    const high = this._val(highId);
    if (low === null || high === null) return `<div class="sub">Comfort range unavailable</div>`;
    const gmin = num((this._state(c.guideline_min) || {}).state);
    const gmax = num((this._state(c.guideline_max) || {}).state);
    const season = (this._state(c.season) || {}).state;
    let note = "";
    if (gmin !== null && gmax !== null) {
      const over = high > gmax ? ` <span class="warn">· your High is ${fmt(high - gmax)} °C above it</span>` : low < gmin ? ` <span class="warn">· your Low is ${fmt(gmin - low)} °C below it</span>` : "";
      note = `Swedish guideline${season ? ` (${esc(season)})` : ""} <b>${fmt(gmin)}–${fmt(gmax)} °C</b>${over}`;
    }
    const guide = gmin !== null && gmax !== null ? `<div class="gl" style="clip-path:inset(0 calc(100% - ${pct(gmax)}) 0 ${pct(gmin)} round 7px)"></div><div class="glt" style="left:${pct(gmin)};width:calc(${pct(gmax)} - ${pct(gmin)})">Guideline</div>` : "";
    const ticks = [];
    for (let t = lo; t <= hi; t += 2) ticks.push(`<div class="tk" style="left:${pct(t)}">${t}</div>`);
    return (
      `<div class="top"><div><div class="range">${fmt(low)} – ${fmt(high)} °C</div><div class="sub">Comfortable range</div></div>${season ? `<span class="chip">${esc(season)}</span>` : ""}</div>` +
      `<div class="sub" style="margin-top:6px">${note}</div>` +
      `<div class="scale"><div class="bar"><div class="dim dl" style="left:0;width:${pct(low)}"></div><div class="dim dr" style="left:${pct(high)};right:0"></div></div>${guide}${ticks.join("")}` +
      `<div class="hl" data-k="low" style="left:${pct(low)}">${fmt(low)}</div><div class="hl" data-k="high" style="left:${pct(high)}">${fmt(high)}</div>` +
      `<div class="hd" role="slider" tabindex="0" aria-label="Comfort low" aria-valuenow="${low}" data-k="low" data-e="${esc(c.low)}" style="left:${pct(low)}"></div>` +
      `<div class="hd" role="slider" tabindex="0" aria-label="Comfort high" aria-valuenow="${high}" data-k="high" data-e="${esc(highId)}" style="left:${pct(high)}"></div></div>`
    );
  }

  _humidity() {
    const h = this._config.humidity;
    if (!h) return "";
    const v = num((this._state(h.entity) || {}).state);
    if (v === null) return "";
    const ceil = this._summer() ? null : num((this._state(h.ceiling) || {}).state);
    const [lo, hi] = h.scale || [20, 80];
    const pct = (x) => `${Math.min(100, Math.max(0, ((x - lo) / (hi - lo)) * 100))}%`;
    const over = ceil !== null && v > ceil;
    const color = over ? "var(--warning-color, #ffa600)" : "var(--primary-color)";
    const text = ceil === null ? `Humidity <b>${fmt(v)} %</b>` : `Humidity <b>${fmt(v)} %</b>, keep under <b>${fmt(ceil)} %</b>${over ? ` <span class="warn">· ventilate</span>` : ""}`;
    return (
      `<div class="line" style="flex-direction:column;align-items:stretch;gap:2px"><div class="sub" style="margin:0">${text}</div>` +
      `<div class="htrack"><div class="hfill" style="width:${pct(v)};--c:${color}"></div>${ceil !== null ? `<div class="hcap" style="left:${pct(ceil)}"></div>` : ""}</div></div>`
    );
  }

  _render() {
    if (!this._config || !this._hass) return;
    const c = this._config;
    const night = c.night_offset ? this._row({ name: "Bedroom cooler at night by", entities: [{ entity: c.night_offset }] }) : "";
    const adv = (c.advanced || [])
      .map((r, i) => (this._show(r.when) ? this._row(r, this._now[i]) : ""))
      .join("");
    this.shadowRoot.innerHTML =
      `<style>${STYLE}</style><ha-card>${this._bar()}${night}${this._humidity()}` +
      (adv ? `<button class="adv"><ha-icon icon="mdi:chevron-${this._open ? "up" : "down"}"></ha-icon>Advanced</button>${this._open ? adv : ""}` : "") +
      `</ha-card>`;
  }
}

customElements.define("comfort-card", ComfortCard);
