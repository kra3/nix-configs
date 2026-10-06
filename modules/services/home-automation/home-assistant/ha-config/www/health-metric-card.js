// Compact health metric card: headline value, delta chip, sparkline and optional sub-metrics.

const MINUS = "−";

const ARROW_PATH = "M5 12h14M13 6l6 6-6 6";

function dayStart(ms) {
  const d = new Date(ms);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
}

function aggregate(values, stat) {
  if (stat === "max") return Math.max(...values);
  if (stat === "min") return Math.min(...values);
  if (stat === "last") return values[values.length - 1];
  return values.reduce((a, b) => a + b, 0) / values.length;
}

// raw: [{t (ms), v}] -> one point per local day, ascending.
function bucketDaily(raw, stat) {
  const days = new Map();
  for (const p of raw) {
    const k = dayStart(p.t);
    if (!days.has(k)) days.set(k, []);
    days.get(k).push(p.v);
  }
  return [...days.entries()]
    .sort((a, b) => a[0] - b[0])
    .map(([t, vs]) => ({ t, v: aggregate(vs, stat) }));
}

const PALETTE = ["#9fa8ff", "#8fd9c0", "#c9a7e8", "#f2c14e"];

// Cumulative sensors chart their daily change; everything else the configured stat.
function popupStat(states, g) {
  const ents = g.entities.map((e) => (typeof e === "string" ? e : e.entity));
  const totals = ents.every((id) => states[id] && ["total", "total_increasing"].includes(states[id].attributes.state_class));
  return totals ? "change" : g.stat || "mean";
}

// list: [{name, color, pts: [{t, v}]}] -> SVG for the popup; bars get one slot per day, stacked sums them.
function chartSvg(list, type, days, stacked, lang) {
  const W = 640;
  const H = 220;
  const L = 44;
  const R = 10;
  const T = 10;
  const B = 24;
  if (!list.some((s) => s.pts.length)) return "";
  const end = dayStart(Date.now());
  const sd = new Date(end);
  sd.setDate(sd.getDate() - (days - 1));
  const t0 = sd.getTime();
  const bar = type === "bar";
  const sums = new Map();
  if (stacked) for (const s of list) for (const p of s.pts) sums.set(dayStart(p.t), (sums.get(dayStart(p.t)) || 0) + p.v);
  const vals = stacked ? [...sums.values()] : list.flatMap((s) => s.pts.map((p) => p.v));
  let hi = Math.max(...vals);
  let lo = bar ? 0 : Math.min(...vals);
  if (hi === lo) hi = lo + 1;
  if (!bar) {
    const pad = (hi - lo) * 0.1;
    hi += pad;
    lo -= pad;
  } else hi *= 1.05;
  const x = (t) => L + ((t - t0) / Math.max(end - t0, 1)) * (W - L - R);
  const y = (v) => T + (1 - (v - lo) / (hi - lo)) * (H - T - B);
  const dec = autoDecimals(hi);
  let out = "";
  for (const f of [0, 0.5, 1]) {
    const v = lo + (hi - lo) * f;
    out += `<line x1="${L}" x2="${W - R}" y1="${y(v).toFixed(1)}" y2="${y(v).toFixed(1)}" class="grid"/><text x="${L - 6}" y="${(y(v) + 4).toFixed(1)}" text-anchor="end">${fmt(v, dec, lang)}</text>`;
  }
  const dl = (t) => new Date(t).toLocaleDateString(lang, { month: "short", day: "numeric" });
  out += `<text x="${L}" y="${H - 6}" text-anchor="start">${dl(t0)}</text><text x="${(L + W - R) / 2}" y="${H - 6}" text-anchor="middle">${dl((t0 + end) / 2)}</text><text x="${W - R}" y="${H - 6}" text-anchor="end">${dl(end)}</text>`;
  const slot = (W - L - R) / days;
  const acc = new Map();
  list.forEach((s, i) => {
    const color = s.color || PALETTE[i % PALETTE.length];
    if (bar) {
      for (const p of s.pts) {
        const k = dayStart(p.t);
        const base = stacked ? acc.get(k) || 0 : 0;
        acc.set(k, base + p.v);
        const top = y(base + p.v);
        const h = Math.max(1.5, y(base) - top);
        const bw = Math.max(2, slot * 0.6);
        out += `<rect x="${(x(k) - bw / 2 + slot / 2).toFixed(1)}" y="${top.toFixed(1)}" width="${bw.toFixed(1)}" height="${h.toFixed(1)}" rx="2" fill="${color}"><title>${dl(k)}: ${fmt(p.v, autoDecimals(p.v), lang)}</title></rect>`;
      }
      return;
    }
    const pts = s.pts.map((p) => [x(p.t), y(p.v), p]);
    if (pts.length > 1) out += `<polyline points="${pts.map((p) => p[0].toFixed(1) + "," + p[1].toFixed(1)).join(" ")}" fill="none" stroke="${color}" stroke-width="2" stroke-linejoin="round"/>`;
    for (const p of pts) out += `<circle cx="${p[0].toFixed(1)}" cy="${p[1].toFixed(1)}" r="${pts.length > 60 ? 1.8 : 3}" fill="${color}"><title>${dl(p[2].t)}: ${fmt(p[2].v, autoDecimals(p[2].v), lang)}</title></circle>`;
  });
  return `<svg class="hmc-chart" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet">${out}</svg>`;
}

// Daily statistics blend the carried-over value into the day of a new reading; recover the reading itself.
function readingsFromMinMax(rows) {
  const out = [];
  let prev = null;
  for (const r of rows) {
    if (r.min === null || r.min === undefined || r.max === null || r.max === undefined) continue;
    const t = typeof r.start === "number" ? r.start : Date.parse(r.start);
    let x;
    if (Math.abs(r.max - r.min) < 1e-9) x = r.min;
    else if (prev === null) continue;
    else x = Math.abs(r.max - prev) < 1e-9 ? r.min : r.max;
    out.push({ t, v: x });
    prev = x;
  }
  return out;
}

// Keep the first point of each run of equal values, so only real readings remain.
function collapseRuns(series) {
  const out = [];
  for (const p of series) {
    if (!out.length || Math.abs(p.v - out[out.length - 1].v) > 1e-9) out.push(p);
  }
  return out;
}

// a/b * 100 for days present in both series.
function ratioSeries(a, b) {
  const byDay = new Map(b.map((p) => [dayStart(p.t), p.v]));
  return a
    .filter((p) => byDay.get(dayStart(p.t)))
    .map((p) => ({ t: p.t, v: (p.v / byDay.get(dayStart(p.t))) * 100 }));
}

// Compare the first and last of the last `points` values.
function computeDelta(series, mode, points) {
  const vals = series.map((p) => p.v);
  const win = points ? vals.slice(-points) : vals;
  if (win.length < 2) return null;
  const first = win[0];
  const last = win[win.length - 1];
  const abs = last - first;
  if (mode === "percent") return first ? { value: (abs / first) * 100, abs } : null;
  return { value: abs, abs };
}

function deltaTone(delta, good) {
  if (!delta || Math.abs(delta.abs) < 1e-9 || good === "none" || !good) return "neutral";
  return (delta.abs > 0) === (good === "up") ? "good" : "bad";
}

function deltaDir(delta) {
  if (!delta || Math.abs(delta.abs) < 1e-9) return "flat";
  return delta.abs > 0 ? "up" : "down";
}

function fmt(value, decimals, lang) {
  return new Intl.NumberFormat(lang, {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(value);
}

function signed(value, decimals, lang) {
  const s = fmt(Math.abs(value), decimals, lang);
  if (Math.abs(value) < Math.pow(10, -decimals) / 2) return s;
  return (value < 0 ? MINUS : "+") + s;
}

function autoDecimals(v) {
  return Math.abs(v) >= 100 ? 0 : 1;
}

function durationText(min, lang) {
  const h = Math.floor(min / 60);
  return `${fmt(h, 0, lang)} h ${fmt(Math.round(min - h * 60), 0, lang)} min`;
}

function durationHtml(min, lang) {
  const h = Math.floor(min / 60);
  const m = Math.round(min - h * 60);
  return `${fmt(h, 0, lang)}<span class="unit">h</span> ${fmt(m, 0, lang)}<span class="unit">min</span>`;
}

// A sensor that exists and currently has a value.
function usable(hass, id) {
  const s = hass.states[id];
  return !!s && s.state !== "unavailable" && s.state !== "unknown";
}

function arrowSvg(dir) {
  const rot = dir === "up" ? -45 : dir === "down" ? 45 : 0;
  return (
    `<svg viewBox="0 0 24 24" width="14" height="14" style="transform:rotate(${rot}deg)">` +
    `<path d="${ARROW_PATH}" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg>`
  );
}

// Sparkline in a 140x52 box. type: "line" (dots on a polyline) or "bar" (one slot per day).
function sparkSvg(series, type, days, color) {
  const W = 140;
  const H = 52;
  const pad = 6;
  const vals = series.map((p) => p.v);
  if (!vals.length) return "";
  const max = Math.max(...vals);
  const min = Math.min(...vals);

  if (type === "bar") {
    const end = dayStart(Date.now());
    const slots = [];
    for (let i = days - 1; i >= 0; i--) {
      const t = new Date(end);
      t.setDate(t.getDate() - i);
      slots.push(t.getTime());
    }
    const byDay = new Map(series.map((p) => [dayStart(p.t), p.v]));
    const slot = W / days;
    const bw = Math.max(2, slot * 0.6);
    const top = Math.max(max, 1e-9);
    let out = "";
    slots.forEach((t, i) => {
      const v = byDay.get(t);
      const cx = slot * i + slot / 2;
      if (!v || v <= 0) {
        out += `<circle cx="${cx.toFixed(1)}" cy="${H - 3}" r="1.4" fill="${color}" opacity="0.45"/>`;
        return;
      }
      const h = Math.max(3, (v / top) * (H - 8));
      const last = i === slots.length - 1;
      out +=
        `<rect x="${(cx - bw / 2).toFixed(1)}" y="${(H - 3 - h).toFixed(1)}" width="${bw.toFixed(1)}" height="${h.toFixed(1)}" ` +
        `rx="${(bw / 2).toFixed(1)}" fill="${color}" opacity="${last ? 1 : 0.85}"/>`;
    });
    return `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet">${out}</svg>`;
  }

  const t0 = series[0].t;
  const t1 = series[series.length - 1].t;
  const xs = (t) => (t1 === t0 ? W / 2 : pad + ((t - t0) / (t1 - t0)) * (W - 2 * pad));
  const ys = (v) => (max === min ? H / 2 : pad + (1 - (v - min) / (max - min)) * (H - 2 * pad));
  const pts = series.map((p) => [xs(p.t), ys(p.v)]);
  const line = pts.map((p) => p[0].toFixed(1) + "," + p[1].toFixed(1)).join(" ");
  const dots = pts
    .map(
      (p, i) =>
        `<circle cx="${p[0].toFixed(1)}" cy="${p[1].toFixed(1)}" r="${i === pts.length - 1 ? 3.4 : 2.4}" ` +
        `fill="${i === pts.length - 1 ? color : "var(--ha-card-background, var(--card-background-color, #1c1c1c))"}" stroke="${color}" stroke-width="1.8"/>`
    )
    .join("");
  const poly =
    pts.length > 1
      ? `<polyline points="${line}" fill="none" stroke="${color}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>`
      : "";
  return `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet">${poly}${dots}</svg>`;
}

const STYLE = `
  :host { display: block; }
  ha-card { overflow: hidden; }
  .card { padding: 14px 16px 12px; cursor: pointer; outline: none; }
  .card:focus-visible { box-shadow: inset 0 0 0 2px color-mix(in srgb, var(--accent) 60%, transparent); }
  .head { display: flex; align-items: center; gap: 8px; }
  .head ha-icon { --mdc-icon-size: 20px; color: var(--accent); }
  .title { font-size: 15px; font-weight: 600; color: var(--primary-text-color); flex: 1; }
  .meta { font-size: 12px; color: var(--secondary-text-color); display: flex; align-items: center; gap: 2px; }
  .meta svg { width: 14px; height: 14px; }
  .body { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-top: 6px; }
  .left { min-width: 0; }
  .hero { display: flex; align-items: baseline; gap: 4px; white-space: nowrap; }
  .value { font-size: 34px; font-weight: 700; line-height: 1.1; letter-spacing: -0.5px; color: var(--primary-text-color); }
  .unit { font-size: 14px; font-weight: 600; color: var(--secondary-text-color); }
  .sub { margin-top: 4px; font-size: 13px; color: var(--secondary-text-color); }
  .spark { flex: 0 1 46%; min-width: 90px; max-width: 200px; }
  .spark svg { width: 100%; height: 56px; display: block; }
  .chip { white-space: nowrap; display: inline-flex; align-items: center; gap: 4px; margin-top: 6px; padding: 2px 10px 2px 6px; border-radius: 999px; font-size: 13px; font-weight: 600; }
  .chip.good { color: var(--success-color, #4caf50); background: color-mix(in srgb, var(--success-color, #4caf50) 16%, transparent); }
  .chip.bad { color: var(--error-color, #f44336); background: color-mix(in srgb, var(--error-color, #f44336) 16%, transparent); }
  .chip.neutral { color: var(--secondary-text-color); background: color-mix(in srgb, var(--secondary-text-color) 14%, transparent); }
  .footer { display: grid; margin-top: 12px; border-top: 1px solid var(--divider-color); }
  .item { display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 10px 0 0; min-width: 0; }
  .item + .item { border-left: 1px solid var(--divider-color); padding-left: 14px; margin-left: 14px; }
  .item .name { display: flex; align-items: center; gap: 6px; font-size: 11px; font-weight: 700; letter-spacing: 0.6px; text-transform: uppercase; color: var(--secondary-text-color); }
  .item .dot { width: 9px; height: 9px; border-radius: 3px; background: var(--dot); }
  .item .change { font-size: 20px; font-weight: 700; color: var(--primary-text-color); margin-top: 2px; }
  .item .now { font-size: 13px; color: var(--secondary-text-color); }
  .badge { width: 30px; height: 30px; border-radius: 50%; display: grid; place-items: center; flex: none; }
  .badge.good { color: #fff; background: var(--success-color, #4caf50); }
  .badge.bad { color: #fff; background: var(--error-color, #f44336); }
  .badge.neutral { color: var(--secondary-text-color); background: color-mix(in srgb, var(--secondary-text-color) 18%, transparent); }
  .empty { font-size: 12px; color: var(--secondary-text-color); }
`;

const POPUP_STYLE = `
  .hmc-overlay { position: fixed; inset: 0; z-index: 1000; background: rgba(0, 0, 0, 0.55); display: flex; align-items: center; justify-content: center; padding: 16px; }
  .hmc-sheet { width: min(760px, 100%); max-height: 90vh; overflow: auto; border-radius: var(--ha-card-border-radius, 16px); background: var(--card-background-color, #1c1c1c); color: var(--primary-text-color); box-shadow: 0 12px 40px rgba(0, 0, 0, 0.5); }
  .hmc-head { position: sticky; top: 0; z-index: 1; display: flex; align-items: center; justify-content: space-between; padding: 14px 16px; background: var(--card-background-color, #1c1c1c); font-size: 18px; font-weight: 600; }
  .hmc-close { border: 0; background: transparent; color: var(--primary-text-color); font-size: 24px; line-height: 1; cursor: pointer; padding: 4px 8px; }
  .hmc-body { display: grid; gap: 12px; padding: 0 16px 16px; }
  .hmc-graph { border: 1px solid var(--divider-color); border-radius: 12px; padding: 12px 14px; }
  .hmc-gtitle { font-size: 15px; font-weight: 600; margin-bottom: 6px; }
  .hmc-chart { width: 100%; height: auto; display: block; }
  .hmc-chart text { fill: var(--secondary-text-color); font-size: 11px; }
  .hmc-chart .grid { stroke: var(--divider-color); stroke-width: 1; }
  .hmc-legend { display: flex; flex-wrap: wrap; gap: 14px; margin-top: 6px; font-size: 12px; color: var(--secondary-text-color); }
  .hmc-legend i { display: inline-block; width: 9px; height: 9px; border-radius: 3px; margin-right: 6px; }
  .hmc-graph .empty { font-size: 12px; color: var(--secondary-text-color); }
`;

class HealthMetricCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.entity) throw new Error("health-metric-card: entity is required");
    this._config = Object.assign({ chart: {}, items: [] }, config);
    this._data = {};
    this._lastFetch = 0;
    this._html = "";
    if (!this.shadowRoot) this.attachShadow({ mode: "open" });
  }

  getCardSize() {
    return this._config && this._config.items.length ? 4 : 3;
  }

  getGridOptions() {
    return { columns: 6, min_columns: 3 };
  }

  set hass(hass) {
    this._hass = hass;
    if (!this._config) return;
    const st = hass.states[this._config.entity];
    const stamp = st ? st.last_updated : "";
    if (stamp !== this._stamp && Date.now() - this._lastFetch > 20000) {
      this._stamp = stamp;
      this._lastFetch = Date.now();
      this._load();
    }
    this._render();
  }

  async _series(entityId, spec) {
    const hass = this._hass;
    const days = spec.days || 7;
    const stat = spec.stat || "mean";
    const scale = spec.scale || 1;
    const now = new Date();
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - (days - 1));
    const st = hass.states[entityId];
    let source = spec.source || "auto";
    if (source === "auto") source = st && st.attributes.state_class ? "statistics" : "history";
    let pts = [];
    if (source === "statistics") {
      try {
        const res = await hass.callWS({
          type: "recorder/statistics_during_period",
          start_time: start.toISOString(),
          end_time: now.toISOString(),
          statistic_ids: [entityId],
          period: "day",
          types: stat === "reading" ? ["min", "max"] : [stat === "last" ? "mean" : stat],
        });
        const rows = res[entityId] || [];
        const key = stat === "last" ? "mean" : stat;
        if (stat === "reading") pts = readingsFromMinMax(rows);
        else pts = rows
          .filter((r) => r[key] !== null && r[key] !== undefined)
          .map((r) => ({ t: typeof r.start === "number" ? r.start : Date.parse(r.start), v: r[key] }));
      } catch (e) {
        pts = [];
      }
      if (!pts.length) source = "history";
    }
    if (source === "history") {
      const res = await hass.callWS({
        type: "history/history_during_period",
        start_time: start.toISOString(),
        end_time: now.toISOString(),
        entity_ids: [entityId],
        minimal_response: true,
        no_attributes: true,
        significant_changes_only: false,
      });
      const raw = (res[entityId] || [])
        .map((r) => ({ t: (r.lu !== undefined ? r.lu : r.lc) * 1000, v: parseFloat(r.s) }))
        .filter((p) => isFinite(p.v) && isFinite(p.t));
      pts = bucketDaily(raw, stat === "reading" ? "last" : stat);
    }
    return pts.map((p) => ({ t: p.t, v: p.v * scale }));
  }

  async _itemSeries(it) {
    const spec = { days: it.days || 30, stat: it.stat || "mean", scale: it.scale, source: it.source };
    const s = await this._series(it.entity, spec);
    if (!it.per) return s;
    return ratioSeries(s, await this._series(it.per, spec));
  }

  async _load() {
    const c = this._config;
    const jobs = [
      this._series(c.entity, c.chart).then((s) => (this._data.main = c.chart.type === "bar" ? s : collapseRuns(s))),
      ...c.items.map((it, i) =>
        this._itemSeries(it).then((s) => (this._data["item" + i] = collapseRuns(s)))
      ),
    ];
    try {
      await Promise.all(jobs);
    } catch (e) {
      /* keep whatever loaded */
    }
    this._render();
  }

  _formatMain(v) {
    const c = this._config;
    const lang = this._hass.language;
    if (c.format === "duration") return { html: durationHtml(v, lang), text: "", unit: "" };
    if (c.format === "distance") {
      return v >= 1000 ? { text: fmt(v / 1000, 1, lang), unit: "km" } : { text: fmt(v, 0, lang), unit: "m" };
    }
    const st = this._hass.states[c.entity];
    const unit = c.unit !== undefined ? c.unit : (st && st.attributes.unit_of_measurement) || "";
    const d = c.decimals !== undefined ? c.decimals : autoDecimals(v);
    return { text: fmt(v, d, lang), unit };
  }

  _metaDate() {
    const c = this._config;
    const src = c.date_entity ? this._hass.states[c.date_entity] : this._hass.states[c.entity];
    if (!src) return "";
    const raw = c.date_entity ? src.state : src.last_updated;
    const ms = Date.parse(raw.includes("T") || raw.includes("Z") ? raw : raw.replace(" ", "T"));
    if (!isFinite(ms)) return "";
    return new Date(ms).toLocaleDateString(this._hass.language, { month: "short", day: "numeric" });
  }

  _render() {
    if (!this._hass || !this._config) return;
    const c = this._config;
    const lang = this._hass.language;
    const st = this._hass.states[c.entity];
    const accent = c.color || "var(--primary-color)";
    const scale = c.scale || 1;
    const raw = st ? parseFloat(st.state) : NaN;
    const hero = isFinite(raw) ? this._formatMain(raw * scale) : { text: "\u2013", unit: "" };
    const heroHtml = hero.html || `<span class="value">${hero.text}</span><span class="unit">${hero.unit}</span>`;

    let under = "";
    const main = this._data.main || [];
    if (c.goal && isFinite(raw)) {
      under = `<div class="sub">${fmt(Math.round((raw / c.goal) * 100), 0, lang)} % Goal</div>`;
    } else if (c.delta && main.length) {
      const d = computeDelta(main, c.delta.mode || "absolute", c.delta.points);
      if (d) {
        const dec = c.delta.decimals !== undefined ? c.delta.decimals : 1;
        const unit = c.delta.mode === "percent" ? "%" : c.delta.unit !== undefined ? c.delta.unit : " " + (hero.unit || "");
        under = `<span class="chip ${deltaTone(d, c.delta.good)}">${arrowSvg(deltaDir(d))}${signed(d.value, dec, lang)}${unit}</span>`;
      }
    }

    if (c.secondary) {
      const sec = this._hass.states[c.secondary.entity];
      const sv = sec ? parseFloat(sec.state) : NaN;
      if (isFinite(sv)) {
        const txt = c.secondary.format === "duration" ? durationText(sv, lang) : fmt(sv, c.secondary.decimals || 0, lang);
        under += `<div class="sub">${c.secondary.prefix || ""}${txt}</div>`;
      }
    }

    const type = c.chart.type || "line";
    const spark = !main.length
      ? `<div class="empty">No data yet</div>`
      : type === "line" && main.length < 2
        ? ""
        : sparkSvg(main, type, c.chart.days || 7, accent);

    const itemHtml = c.items
      .map((it, i) => {
        if (!usable(this._hass, it.entity)) return "";
        const s = this._data["item" + i] || [];
        const ist = this._hass.states[it.entity];
        const mode = it.mode || "absolute";
        const d = computeDelta(s, mode, it.points);
        const tone = deltaTone(d, it.good);
        const unit = it.unit !== undefined ? it.unit : it.per ? "%" : (ist && ist.attributes.unit_of_measurement) || "";
        const dec = it.decimals !== undefined ? it.decimals : 1;
        const pst = it.per ? this._hass.states[it.per] : null;
        const nowRaw = ist ? parseFloat(ist.state) * (it.scale || 1) : NaN;
        const nowVal = it.per ? (pst ? (nowRaw / parseFloat(pst.state)) * 100 : NaN) : nowRaw;
        const now = isFinite(nowVal) ? fmt(nowVal, dec, lang) : "–";
        let alsoTxt = "";
        if (it.also) {
          const ast = this._hass.states[it.also.entity];
          const av = ast ? parseFloat(ast.state) : NaN;
          if (isFinite(av)) {
            const au = it.also.unit !== undefined ? it.also.unit : (ast.attributes.unit_of_measurement || "");
            alsoTxt = `${fmt(av, it.also.decimals !== undefined ? it.also.decimals : 1, lang)} ${au} \u00b7 `;
          }
        }
        const change = d ? signed(d.value, dec, lang) + (mode === "percent" ? "%" : "") : "–";
        return (
          `<div class="item" style="--dot:${it.color || accent}"><div><div class="name"><span class="dot"></span>${it.name || ""}</div>` +
          `<div class="change">${change}</div><div class="now">${alsoTxt}${now} ${unit}</div></div>` +
          `<span class="badge ${tone}">${arrowSvg(deltaDir(d))}</span></div>`
        );
      })
      .filter(Boolean);
    const items = itemHtml.join("");

    const date = c.show_date === false ? "" : this._metaDate();
    const html =
      `<style>${STYLE}</style><ha-card style="--accent:${accent}">` +
      `<div class="card" role="button" tabindex="0">` +
      `<div class="head">${c.icon ? `<ha-icon icon="${c.icon}"></ha-icon>` : ""}<span class="title">${c.name || (st && st.attributes.friendly_name) || ""}</span>` +
      `<span class="meta">${date}<svg viewBox="0 0 24 24"><path d="M9 6l6 6-6 6" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg></span></div>` +
      `<div class="body"><div class="left"><div class="hero">${heroHtml}</div>${under}</div>` +
      `<div class="spark">${spark}</div></div>` +
      (items ? `<div class="footer" style="grid-template-columns:repeat(${itemHtml.length},1fr)">${items}</div>` : "") +
      `</div></ha-card>`;

    if (html === this._html) return;
    this._html = html;
    this.shadowRoot.innerHTML = html;
    const el = this.shadowRoot.querySelector(".card");
    el.addEventListener("click", () => this._tap());
    el.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") this._tap();
    });
  }

  async _openPopup() {
    if (this._overlay) return;
    const c = this._config;
    if (!document.getElementById("hmc-popup-style")) {
      const st = document.createElement("style");
      st.id = "hmc-popup-style";
      st.textContent = POPUP_STYLE;
      document.head.appendChild(st);
    }
    const ov = document.createElement("div");
    ov.className = "hmc-overlay";
    ov.innerHTML = `<div class="hmc-sheet" role="dialog" aria-modal="true"><div class="hmc-head"><span class="hmc-title"></span><button class="hmc-close" aria-label="Close">\u00d7</button></div><div class="hmc-body"></div></div>`;
    ov.querySelector(".hmc-title").textContent = c.popup.title || c.name || "";
    const close = () => {
      document.removeEventListener("keydown", onKey);
      ov.remove();
      this._overlay = null;
    };
    const onKey = (e) => {
      if (e.key === "Escape") close();
    };
    ov.addEventListener("click", (e) => {
      if (e.target === ov) close();
    });
    ov.querySelector(".hmc-close").addEventListener("click", close);
    document.addEventListener("keydown", onKey);
    document.body.appendChild(ov);
    this._overlay = ov;
    const body = ov.querySelector(".hmc-body");
    const lang = this._hass.language;
    const shown = c.popup.graphs.filter((g) => g.entities.some((e) => usable(this._hass, typeof e === "string" ? e : e.entity)));
    await Promise.all(
      shown.map(async (g) => {
        const sec = document.createElement("div");
        sec.className = "hmc-graph";
        const title = document.createElement("div");
        title.className = "hmc-gtitle";
        title.textContent = g.name;
        const box = document.createElement("div");
        box.textContent = "Loading…";
        sec.appendChild(title);
        sec.appendChild(box);
        body.appendChild(sec);
        const stat = popupStat(this._hass.states, g);
        const ents = g.entities.map((e) => (typeof e === "string" ? { entity: e } : e)).filter((e) => usable(this._hass, e.entity));
        const list = await Promise.all(
          ents.map(async (e) => {
            let pts = [];
            try {
              pts = await this._series(e.entity, { days: g.days || 30, stat, scale: g.scale });
            } catch (err) {
              /* leave empty */
            }
            return { name: e.name, color: e.color || (ents.length === 1 ? c.color : undefined), pts: g.type === "bar" ? pts : collapseRuns(pts) };
          })
        );
        const svg = chartSvg(list, g.type || "line", g.days || 30, !!g.stacked, lang);
        const legend =
          list.length > 1
            ? `<div class="hmc-legend">${list.map((s, i) => `<span><i style="background:${s.color || PALETTE[i % PALETTE.length]}"></i>${s.name}</span>`).join("")}</div>`
            : "";
        box.innerHTML = svg ? svg + legend : `<div class="empty">No data yet</div>`;
      })
    );
  }

  _tap() {
    if (this._config.popup) {
      this._openPopup();
      return;
    }
    const a = this._config.tap_action;
    if (a && a.action === "navigate" && a.navigation_path) {
      history.pushState(null, "", a.navigation_path);
      window.dispatchEvent(new Event("location-changed"));
      return;
    }
    this.dispatchEvent(
      new CustomEvent("hass-more-info", { detail: { entityId: this._config.entity }, bubbles: true, composed: true })
    );
  }
}

if (typeof customElements !== "undefined" && !customElements.get("health-metric-card")) {
  customElements.define("health-metric-card", HealthMetricCard);
  window.customCards = window.customCards || [];
  window.customCards.push({
    type: "health-metric-card",
    name: "Health metric card",
    description: "Headline value, delta chip, sparkline and optional sub-metrics.",
  });
}

if (typeof module !== "undefined") {
  module.exports = { usable, popupStat, chartSvg, readingsFromMinMax, collapseRuns, ratioSeries, durationHtml, bucketDaily, computeDelta, deltaTone, deltaDir, signed, fmt, sparkSvg, dayStart };
}
