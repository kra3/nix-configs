// Explains why each room's light is on or off: outside daylight model, per-room verdict and tunable thresholds.

const STYLE = `
  :host { display: block; }
  ha-card { overflow: hidden; }
  .blk { padding: 10px 16px; min-height: 44px; box-sizing: border-box; cursor: pointer; }
  .blk + .blk { border-top: 1px solid var(--divider-color); }
  .hd { display: flex; align-items: center; gap: 10px; min-width: 0; }
  ha-icon { --mdc-icon-size: 22px; flex: none; color: var(--c); }
  .tx { flex: 1; min-width: 0; display: flex; flex-direction: column; }
  @media (min-width: 481px) { .tx { flex-direction: row; flex-wrap: wrap; align-items: baseline; column-gap: 10px; } }
  .nm { font-size: 15px; font-weight: 600; color: var(--primary-text-color); overflow-wrap: anywhere; }
  .sub, .hint { font-size: 12px; line-height: 1.35; color: var(--secondary-text-color); overflow-wrap: anywhere; }
  .vd { font-size: 13px; font-weight: 500; color: var(--c); overflow-wrap: anywhere; }
  .dk { display: flex; flex-wrap: wrap; align-items: baseline; gap: 2px 6px; margin: 2px 0 0 32px; font-size: 12px; line-height: 1.35; color: var(--secondary-text-color); }
  .mini { font-size: 11px; font-weight: 500; white-space: nowrap; }
  .mini.ok { color: var(--success-color); }
  .mini.no { color: var(--error-color); }
  .mini.na { color: var(--state-inactive-color); }
  .rule { padding: 10px 16px 0; font-size: 12px; line-height: 1.35; color: var(--secondary-text-color); }
  .lx { font-size: 12px; color: var(--secondary-text-color); white-space: nowrap; }
  .bar { position: relative; height: 8px; border-radius: 4px; background: var(--divider-color, rgba(127,127,127,.25)); margin: 16px 6px 20px; }
  .bar.sm { margin: 10px 6px 18px 32px; height: 6px; }
  .fill { position: absolute; left: 0; top: 0; bottom: 0; border-radius: 4px; background: var(--c); }
  .bar.ia .fill { background: var(--secondary-text-color); }
  .tk { position: absolute; top: -4px; bottom: -4px; width: 2px; margin-left: -1px; background: var(--secondary-text-color); }
  .tk span { position: absolute; top: 100%; left: 50%; transform: translateX(-50%); font-size: 10px; line-height: 1.2; white-space: nowrap; color: var(--secondary-text-color); }
  .tk.up span { top: auto; bottom: 100%; }
  .row { display: flex; flex-wrap: wrap; align-items: center; gap: 4px 8px; }
  .chip { display: inline-flex; align-items: center; min-height: 22px; padding: 0 8px; border-radius: 11px; font-size: 11px; font-weight: 500; background: var(--secondary-background-color); color: var(--primary-text-color); }
  .chip.ok { color: var(--success-color); }
  .chip.no { color: var(--error-color); }
  .chip.na { color: var(--state-inactive-color); }
  .ex { padding: 6px 0 2px 32px; display: flex; flex-direction: column; gap: 8px; cursor: default; }
  .sl { cursor: default; }
  .sl .top { display: flex; justify-content: space-between; flex-wrap: wrap; gap: 0 8px; font-size: 13px; color: var(--primary-text-color); }
  .sl .top span { color: var(--secondary-text-color); font-size: 12px; }
  .seg { display: flex; gap: 0; }
  .seg button, .stp button { min-height: 44px; border: 1px solid var(--divider-color); background: var(--secondary-background-color); color: var(--primary-text-color); font: inherit; font-size: 14px; cursor: pointer; }
  .seg button { flex: 1; }
  .seg button:first-child { border-radius: 22px 0 0 22px; }
  .seg button:last-child { border-radius: 0 22px 22px 0; }
  .seg button.on { background: var(--primary-color); border-color: var(--primary-color); color: var(--text-primary-color, #fff); }
  .stp { display: flex; align-items: center; justify-content: center; flex-wrap: wrap; gap: 8px; font-size: 13px; color: var(--primary-text-color); }
  .stp button { min-width: 44px; border-radius: 22px; font-size: 20px; }
  .band, .eb { position: relative; }
  .band { height: 44px; margin-top: 22px; }
  .trk { position: absolute; left: 14px; right: 14px; top: 18px; height: 8px; border-radius: 4px; background: var(--secondary-background-color); }
  .shade { position: absolute; top: 0; bottom: 0; border-radius: 4px; background: var(--primary-color); opacity: 0.45; }
  .mk { position: absolute; top: -20px; transform: translateX(-50%); font-size: 11px; line-height: 1; white-space: nowrap; color: var(--c); }
  .mk.r { transform: translateX(-100%); }
  .mk.l { transform: none; }
  .eb { margin-left: 18px; padding: 19px 14px; }
  .eb .bar { margin: 0; }
  .band input, .eb input { position: absolute; left: 0; top: 0; width: 100%; height: 44px; margin: 0; padding: 0; background: transparent; pointer-events: none; -webkit-appearance: none; appearance: none; }
  .eb input { top: 50%; margin-top: -22px; }
  input[type=range]::-webkit-slider-runnable-track { height: 44px; background: transparent; }
  input[type=range]::-moz-range-track { height: 44px; background: transparent; }
  input[type=range]::-webkit-slider-thumb { -webkit-appearance: none; box-sizing: border-box; width: 28px; height: 28px; margin-top: 8px; border-radius: 50%; border: 2px solid #fff; background: var(--primary-color); box-shadow: 0 1px 3px rgba(0,0,0,.4); pointer-events: auto; cursor: pointer; }
  input[type=range]::-moz-range-thumb { box-sizing: border-box; width: 28px; height: 28px; border-radius: 50%; border: 2px solid #fff; background: var(--primary-color); box-shadow: 0 1px 3px rgba(0,0,0,.4); pointer-events: auto; cursor: pointer; }
`;

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const TONES = { success: "var(--success-color)", warning: "var(--warning-color)", error: "var(--error-color)", info: "var(--info-color)", inactive: "var(--state-inactive-color)" };
const ROOM_KEYS = ["light", "dark", "occupancy", "lux", "threshold", "block", "nap"];
const fmt = (n, d = 0) => Number(n.toFixed(d)).toString();

class LightLogicCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.outside || !Array.isArray(config.rooms) || !config.rooms.length) throw new Error("light-logic-card: outside and rooms are required");
    this._config = config;
    this._ids = [...Object.values(config.outside).filter((v) => typeof v === "string"), ...Object.values(config.house || {}), ...config.rooms.flatMap((r) => ROOM_KEYS.map((k) => r[k]))].filter(Boolean);
    this._open = -1;
    this._outOpen = false;
    this._sig = null;
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      const sr = this.shadowRoot;
      sr.addEventListener("click", (e) => {
        const sg = e.target.closest("[data-seg]");
        const st = e.target.closest("[data-step]");
        if (sg) { this._seg = sg.dataset.seg; return this._render(); }
        if (st) return this._step(Number(st.dataset.step));
        if (e.target.closest(".sl")) return;
        const el = e.target.closest("[data-act]");
        if (!el) return;
        if (el.dataset.act === "out") { this._outOpen = !this._outOpen; this._seg = null; }
        else this._open = this._open === Number(el.dataset.i) ? -1 : Number(el.dataset.i);
        this._render();
      });
      sr.addEventListener("pointerdown", (e) => { if (e.target.closest("input")) this._drag = true; });
      const up = () => { if (this._drag) { this._drag = false; this.hass = this._hass; } };
      window.addEventListener("pointerup", up);
      window.addEventListener("pointercancel", up);
      sr.addEventListener("input", (e) => {
        const el = e.target.closest("input[data-ent]");
        if (!el) return;
        this._clamp(el);
        if (el.dataset.band) this._bandLive();
        else { const l = sr.querySelector(".tlab"); if (l) l.textContent = this._tlab(el.dataset.unit, Number(el.value), el.dataset.def === "" ? null : Number(el.dataset.def)); }
      });
      sr.addEventListener("change", (e) => {
        const el = e.target.closest("input[data-ent]");
        if (!el) return;
        this._clamp(el);
        this._drag = false;
        this._call(el.dataset.ent, Number(el.value));
      });
    }
    this._render();
  }

  set hass(hass) {
    this._hass = hass;
    if (this._drag) return;
    const ad = this._config.house && this._config.house.adaptive;
    const sig = JSON.stringify(this._ids.map((id) => {
      const s = hass.states[id];
      if (!s) return null;
      if (id === ad) return JSON.stringify(s.attributes.manual_control);
      if (id.startsWith("input_number.")) { const a = s.attributes; return [s.state, a.min, a.max, a.step, a.default]; }
      return s.state;
    }));
    if (sig === this._sig) return;
    this._sig = sig;
    this._render();
  }

  getCardSize() {
    return 3 + this._config.rooms.length;
  }

  _val(id) {
    const s = id && this._hass && this._hass.states[id];
    return !s || s.state === "unavailable" || s.state === "unknown" ? null : s.state;
  }

  _num(id) {
    const v = this._val(id);
    return v === null || v === "" || isNaN(Number(v)) ? null : Number(v);
  }

  _on(id) {
    return this._val(id) === "on";
  }

  _inv(id) {
    const v = this._val(id);
    return v === null ? null : v === "on" ? "off" : "on";
  }

  _thr(r) {
    return (r.threshold ? this._num(r.threshold) : null) ?? this._attrs(r.threshold).default ?? null;
  }


  _attrs(id) {
    const s = this._hass.states[id];
    return s ? s.attributes : {};
  }

  _call(id, value) {
    this._hass.callService("input_number", "set_value", { entity_id: id, value });
  }

  _step(dir) {
    const o = this._config.outside;
    const a = this._attrs(o.evening_offset);
    const v = this._num(o.evening_offset) ?? a.default ?? 60;
    const n = Math.min(a.max ?? 180, Math.max(a.min ?? 0, v + dir * (a.step ?? 15)));
    if (n !== v) this._call(o.evening_offset, n);
  }

  _clamp(el) {
    let v = Math.min(Number(el.dataset.max ?? el.max), Math.max(Number(el.dataset.min ?? el.min), Number(el.value)));
    if (el.dataset.band) {
      const other = this.shadowRoot.querySelector(`input[data-band=${el.dataset.band === "lo" ? "hi" : "lo"}]`);
      v = el.dataset.band === "lo" ? Math.min(v, Number(other.value) - 2) : Math.max(v, Number(other.value) + 2);
    }
    el.value = v;
  }

  _bandText(g, c) {
    return `gloomy &lt;${fmt(g)} %  ·  light &gt;${fmt(c)} %`;
  }

  _tip(gl, sun, g, c) {
    const o = this._config.outside;
    const act = this._on(o.evening_rule) ? "evening" : "day";
    if ((this._seg || act) !== act) g = this._gl(act)[0];
    if (gl === null) return "";
    if (sun === "below_horizon") return "Sun is down · rooms may light up until sunrise";
    return gl === "on" ? `Stays gloomy until daylight is above ${fmt(c)} % for 10 min` : `Lights stay off · goes gloomy below ${fmt(g)} %`;
  }

  _bandLive() {
    const sr = this.shadowRoot;
    const g = Number(sr.querySelector("input[data-band=lo]").value);
    const c = Number(sr.querySelector("input[data-band=hi]").value);
    const sh = sr.querySelector(".shade");
    sh.style.left = `${(g / 50) * 100}%`;
    sh.style.width = `${((c - g) / 50) * 100}%`;
    sr.querySelector(".glab b").innerHTML = this._bandText(g, c);
    sr.querySelector(".tip").textContent = this._tip(this._val(this._config.outside.gloomy), this._val(this._config.outside.sun), g, c);
  }

  _tlab(unit, v, def) {
    return `dark below ${fmt(v)} ${unit || ""} ${Number.isNaN(def) || def == null ? "" : `· default ${fmt(def)}`}`.trim();
  }

  _gl(sel) {
    const o = this._config.outside;
    const k = `gloomy_below_${sel}`;
    return [this._num(o[k]) ?? this._attrs(o[k]).default ?? (sel === "day" ? 5 : 15), this._num(o.clear_above) ?? this._attrs(o.clear_above).default ?? 22];
  }

  _outside() {
    const o = this._config.outside;
    const ev = this._on(o.evening_rule);
    const act = ev ? "evening" : "day";
    const sel = this._seg || act;
    const [g, c] = this._gl(this._outOpen ? sel : act);
    const gl = this._val(o.gloomy);
    const frac = this._num(o.fraction);
    const sun = this._val(o.sun);
    const tn = gl === null ? "inactive" : gl === "on" ? "warning" : "success";
    const ref = this._num(o.reference);
    const peak = this._num(o.peak);
    const line = (sun === "below_horizon" ? "Sun down · dark regardless" : `${ref === null ? "no data" : fmt(ref) + " lx"} now · peak ${peak === null ? "no data" : fmt(peak) + " lx"} · ${sun === null ? "sun no data" : "sun up"}`) + ` · ${act} rule`;
    const pos = (p) => Math.min(100, Math.max(0, (p / 50) * 100));
    let mid;
    if (this._outOpen) {
      const ga = this._attrs(o[`gloomy_below_${sel}`]);
      const ca = this._attrs(o.clear_above);
      const oa = this._attrs(o.evening_offset);
      const ov = this._num(o.evening_offset) ?? oa.default ?? 60;
      const inp = (id, band, v, a, st) => `<input type="range" data-ent="${esc(id)}" data-band="${band}" data-min="${a.min ?? 0}" data-max="${a.max ?? 50}" min="0" max="50" step="${st}" value="${v}" style="z-index:${band === "lo" ? (g >= 25 ? 2 : 1) : 1}">`;
      const seg = ["day", "evening"].map((s) => `<button type="button" data-seg="${s}" class="${s === sel ? "on" : ""}">${s === "day" ? "Day" : "Evening"}</button>`).join("");
      mid = `<div class="ex sl"><div class="seg">${seg}</div>` +
        `<div class="band" style="--c:${TONES[tn]}"><div class="trk"><div class="shade" style="left:${pos(g)}%;width:${pos(c) - pos(g)}%"></div>` +
        `${frac === null ? "" : `<div class="mk${pos(frac * 100) > 80 ? " r" : pos(frac * 100) < 20 ? " l" : ""}" style="left:${pos(frac * 100)}%">${pos(frac * 100) > 80 ? `now ${fmt(frac * 100, 1)} % ▼` : `▼ now ${fmt(frac * 100, 1)} %`}</div>`}</div>` +
        `${inp(o[`gloomy_below_${sel}`], "lo", g, ga, ga.step ?? 1)}${inp(o.clear_above, "hi", c, ca, ca.step ?? 1)}</div>` +
        `<div class="top glab"><b>${this._bandText(g, c)}</b><span>default ${fmt(ga.default ?? 0)}/${fmt(ca.default ?? 0)}</span></div>` +
        `<div class="stp">Evening from <button type="button" data-step="-1" aria-label="earlier">−</button> ${fmt(ov)} ${esc(oa.unit_of_measurement || "min")} before sunset <button type="button" data-step="1" aria-label="later">+</button></div></div>`;
    } else {
      mid = `<div class="bar${tn === "inactive" ? " ia" : ""}" style="--c:${TONES[tn]}">${frac === null ? "" : `<div class="fill" style="width:${pos(frac * 100)}%"></div>`}` +
        `<div class="tk" style="left:${pos(g)}%"><span>gloomy &lt;${fmt(g)} %</span></div><div class="tk up" style="left:${pos(c)}%"><span>light &gt;${fmt(c)} %</span></div></div>`;
    }
    return `<div class="blk" data-act="out" style="--c:${TONES[tn]}"><div class="hd"><ha-icon icon="${gl === "on" ? "mdi:weather-cloudy" : "mdi:weather-sunny"}"></ha-icon>` +
      `<div class="tx"><div class="nm">${gl === null ? "Outside: no data" : gl === "on" ? "Gloomy outside · rooms may light up" : "Light outside"}</div>` +
      `<div class="sub">${frac === null ? "daylight no data" : `daylight ${fmt(frac * 100, 1)} % of today's peak`}</div></div></div>` +
      `${mid}<div class="sub tip">${esc(this._tip(gl, sun, g, c))}</div>${this._outOpen ? `<div class="sub">${esc(line)}</div>` : ""}</div>`;
  }


  _verdict(r) {
    const h = this._config.house || {};
    const [g] = this._gl(this._on(this._config.outside.evening_rule) ? "evening" : "day");
    const dark = this._val(r.dark);
    const light = this._val(r.light);
    const lux = r.lux ? this._num(r.lux) : null;
    const T = this._thr(r);
    let t;
    if (this._on(h.paused)) t = ["Paused · automations off", "warning"];
    else if (["pending", "triggered"].includes(this._val(h.alarm))) t = ["Alarm · automations stand by", "error"];
    else if (this._val(h.home) === "off" && (r.evening_hold || r.away_off)) t = ["Nobody home · off", "inactive"];
    else if (light !== "on" && ((r.sleep_off && this._on(h.sleep)) || this._on(r.nap))) t = [this._on(r.nap) ? "Nap · off until it ends" : "Sleep · stays off", "inactive"];
    else if (light !== "on" && this._on(r.block)) t = ["Film playing · kept off", "inactive"];
    else if (dark === null) t = ["no data", "inactive"];
    else if (dark === "off") {
      const soon = this._val(this._config.outside.gloomy) === "on" && (!r.lux || (lux !== null && T !== null && lux < T));
      t = soon ? ["Off · getting dark", "info"] : ["Off · not dark", "inactive"];
    } else if (light === "on") {
      if (this._on(r.occupancy)) t = ["On · dark + someone in", "success"];
      else if (r.evening_hold) t = [this._on(h.sleep) ? "Bedtime · off once empty" : "Evening hold · stays on until bedtime", "success"];
      else t = ["On", "success"];
    } else if (light === null) t = ["no data", "inactive"];
    else t = ["Dark · on when someone enters", "info"];
    if (light === "on" && ((r.sleep_off && this._on(h.sleep)) || this._on(r.nap) || this._on(r.block))) t[0] += " · by hand";
    return t;
  }

  _dark(r) {
    const dark = this._val(r.dark);
    const gl = this._val(this._config.outside.gloomy);
    const [g, c] = this._gl(this._on(this._config.outside.evening_rule) ? "evening" : "day");
    const lux = r.lux ? this._num(r.lux) : null;
    const T = this._thr(r);
    const dim = lux !== null && T !== null ? lux < T : null;
    const mark = (ok, label) => `<span class="mini ${ok === null ? "na" : ok ? "ok" : "no"}">${ok === null ? "?" : ok ? "✓" : "✗"} ${label}</span>`;
    const ticks = mark(gl === null ? null : gl === "on", "gloomy") + (r.lux ? mark(dim, T === null ? "lux" : `&lt;${fmt(T)} lx`) : "");
    let t;
    if (dark === null) t = "no data";
    else if (dark === "on") {
      const lc = this._hass.states[r.dark].last_changed;
      t = `Dark since ${new Date(lc).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })} · until it's light outside (&gt;${fmt(c)} %)`;
    } else if (!r.lux) t = gl === "on" ? "Dark any moment · no sensor, follows outside" : "Not dark · no sensor, dark when it's gloomy outside";
    else if (dim === null) t = "Not dark · room lux no data";
    else if (gl === "on") t = dim ? `Dark in ≤2 min · gloomy and ${fmt(lux)} &lt; ${fmt(T)} lx` : `Not dark · needs below ${fmt(T)} lx (now ${fmt(lux)})`;
    else t = dim ? `Not dark · dim enough (${fmt(lux)} &lt; ${fmt(T)} lx), waiting for gloomy outside (&lt;${fmt(g)} %)` : `Not dark · needs gloomy outside and below ${fmt(T)} lx (now ${fmt(lux)})`;
    return `<div class="dk">${dark === "on" ? "" : ticks}<span>${t}</span></div>`;
  }

  _chk(label, v) {
    return `<span class="chip ${v === null ? "na" : v === "on" ? "ok" : "no"}">${v === null ? "?" : v === "on" ? "✓" : "✗"} ${esc(label)}${v === null ? " · no data" : ""}</span>`;
  }

  _room(r, i) {
    const h = this._config.house || {};
    const [text, tn] = this._verdict(r);
    const lux = r.lux ? this._num(r.lux) : null;
    const T = this._thr(r);
    let luxHtml = `<span class="lx">no sensor</span>`;
    let bar = "";
    if (r.lux) {
      luxHtml = `<span class="lx">${lux === null ? "no data" : fmt(lux) + " lx"}</span>`;
      if (lux !== null) {
        const edit = this._open === i && r.threshold && T !== null && this._hass.states[r.threshold];
        const ta = edit ? this._attrs(r.threshold) : {};
        const max = edit ? ta.max ?? 100 : Math.max((T || 0) * 2, lux, 1);
        const b = `<div class="bar sm${tn === "inactive" ? " ia" : ""}" style="--c:${TONES[tn]}"><div class="fill" style="width:${Math.min(100, (lux / max) * 100)}%"></div>` + (edit || T === null ? "" : `<div class="tk" style="left:${(T / max) * 100}%"><span>&lt;${fmt(T)}</span></div>`) + `</div>`;
        bar = edit ? `<div class="eb sl">${b.replace("bar sm", "bar")}<input type="range" data-ent="${esc(r.threshold)}" data-unit="${esc(ta.unit_of_measurement || "")}" data-def="${ta.default ?? ""}" min="${ta.min ?? 0}" max="${max}" step="${ta.step ?? 1}" value="${T}"></div><div class="sl" style="margin-left:32px"><div class="top tlab">${this._tlab(ta.unit_of_measurement, T, ta.default)}</div></div>` : b;
      }
    }
    const ad = this._hass.states[h.adaptive];
    const manual = ad && Array.isArray(ad.attributes.manual_control) && ad.attributes.manual_control.includes(r.light);
    const chips = (this._on(h.party) ? `<span class="chip">Party</span>` : "") + (manual ? `<span class="chip">Manual</span>` : "");
    let ex = "";
    if (this._open === i) {
      const checks = [
        this._chk("Dark", this._val(r.dark)),
        this._chk("Someone in", this._val(r.occupancy)),
        r.sleep_off ? this._chk("Not sleep hours", this._inv(h.sleep)) : "",
        r.block ? this._chk("No film", this._inv(r.block)) : "",
        r.evening_hold || r.away_off ? this._chk("Home", this._val(h.home)) : "",
        this._chk("Not paused", this._inv(h.paused)),
      ].join("");
      const hint = r.hint ? esc(r.hint) : r.evening_hold ? "Stays on from dark until bedtime while anyone is home; dims to 15 % when empty for 2 min" : "Turns off 2 min after the room clears";
      ex = `<div class="ex"><div class="row">${checks}</div><div class="hint">${hint}</div></div>`;
    }
    return `<div class="blk" data-act="room" data-i="${i}" style="--c:${TONES[tn]}"><div class="hd"><ha-icon icon="${this._on(r.light) ? "mdi:lightbulb-on" : "mdi:lightbulb-outline"}"></ha-icon>` +
      `<div class="tx"><div class="row"><span class="nm">${esc(r.name)}</span>${chips}</div><div class="vd">${esc(text)}</div></div>${luxHtml}</div>${this._dark(r)}${bar}${ex}</div>`;
  }

  _render() {
    if (!this._config || !this._hass) return;
    const fa = this.shadowRoot.activeElement;
    const fe = fa && fa.dataset && fa.dataset.ent;
    const fb = fa && fa.dataset && fa.dataset.band;
    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card><div class="rule">A room is dark when it's gloomy outside and below its lux mark for 2 min. It stays dark until it's light outside.</div>${this._outside()}${this._config.rooms.map((r, i) => this._room(r, i)).join("")}</ha-card>`;
    if (fe) {
      const n = [...this.shadowRoot.querySelectorAll("input[data-ent]")].find((i) => i.dataset.ent === fe && i.dataset.band === fb);
      if (n) n.focus();
    }
  }
}

customElements.define("light-logic-card", LightLogicCard);
