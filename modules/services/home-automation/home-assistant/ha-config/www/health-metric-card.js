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
const DUR_STEPS = [30, 60, 120, 180, 240, 360, 480];
const RANGES = [[7, "Week"], [30, "Month"], [90, "3M"], [180, "6M"]];
const TONE_COLOR = { good: "#7ccf7c", mid: "#f2c14e", bad: "#f08a80" };
let chartSeq = 0;

// Cumulative sensors chart their daily change; everything else the configured stat.
function popupStat(states, g) {
  const ents = g.entities.map((e) => (typeof e === "string" ? e : e.entity));
  const totals = ents.every((id) => states[id] && ["total", "total_increasing"].includes(states[id].attributes.state_class));
  return totals ? "change" : g.stat || "mean";
}

function shortDur(min) {
  const h = Math.floor(min / 60);
  return `${h}h ${String(Math.round(min - h * 60)).padStart(2, "0")}m`;
}

// Smooth curve through [[x, y]] without overshooting between points.
function smoothPath(pts) {
  const f = (n) => n.toFixed(1);
  if (pts.length < 3) return "M" + pts.map((p) => f(p[0]) + "," + f(p[1])).join("L");
  let d = `M${f(pts[0][0])},${f(pts[0][1])}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[i - 1] || pts[i];
    const p1 = pts[i];
    const p2 = pts[i + 1];
    const p3 = pts[i + 2] || p2;
    const lo = Math.min(p1[1], p2[1]);
    const hi = Math.max(p1[1], p2[1]);
    const c1 = Math.min(hi, Math.max(lo, p1[1] + (p2[1] - p0[1]) / 6));
    const c2 = Math.min(hi, Math.max(lo, p2[1] - (p3[1] - p1[1]) / 6));
    d += `C${f(p1[0] + (p2[0] - p0[0]) / 6)},${f(c1)} ${f(p2[0] - (p3[0] - p1[0]) / 6)},${f(c2)} ${f(p2[0])},${f(p2[1])}`;
  }
  return d;
}

// Round tick values (multiples of a nice step) inside [lo, hi].
function niceTicks(lo, hi, steps) {
  const rough = (hi - lo) / 3;
  const p = Math.pow(10, Math.floor(Math.log10(rough)));
  const list = steps || [1, 2, 2.5, 5, 10].map((m) => m * p);
  const step = list.find((s) => s >= rough) || list[list.length - 1];
  const out = [];
  for (let v = Math.ceil(lo / step) * step; v <= hi + 1e-9; v += step) out.push(v);
  return out.length ? out : [(lo + hi) / 2];
}

function pill(label, y, W) {
  const w = Math.max(32, label.length * 6.6 + 12);
  return `<rect class="pill" x="${(W - w).toFixed(1)}" y="${(y - 9).toFixed(1)}" width="${w.toFixed(1)}" height="18" rx="9"/><text class="pilltxt" x="${(W - w / 2).toFixed(1)}" y="${(y + 4).toFixed(1)}" text-anchor="middle">${label}</text>`;
}

// list: [{name, color, pts: [{t, v}]}]; bars get one slot per day, stacked sums them.
// opts: {end (ms, last day), fmt (hover), axisFmt (y pills)}
function chartSvg(list, type, days, stacked, lang, opts = {}) {
  const W = 640;
  const H = 220;
  const L = 8;
  const R = 54;
  const T = 12;
  const B = 24;
  if (!list.some((s) => s.pts.length)) return "";
  const end = opts.end || dayStart(Date.now());
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
    const pad = (hi - lo) * 0.12;
    hi += pad;
    lo -= pad;
  } else hi *= 1.05;
  const x = (t) => L + ((t - t0) / Math.max(end - t0, 1)) * (W - L - R);
  const y = (v) => T + (1 - (v - lo) / (hi - lo)) * (H - T - B);
  const hf = opts.fmt || ((v) => fmt(v, autoDecimals(v), lang));
  const af = opts.axisFmt || ((v) => fmt(v, autoDecimals(hi), lang));
  const dl = (t) => new Date(t).toLocaleDateString(lang, { month: "short", day: "numeric" });
  const id = "hmc" + ++chartSeq;
  let out = "";
  const ticks = niceTicks(lo, hi, opts.steps);
  for (const v of ticks) out += `<line class="grid" x1="${L}" x2="${W - R / 2}" y1="${y(v).toFixed(1)}" y2="${y(v).toFixed(1)}"/>`;
  out += `<text x="${L}" y="${H - 6}" text-anchor="start">${dl(t0)}</text><text x="${((L + W - R) / 2).toFixed(1)}" y="${H - 6}" text-anchor="middle">${dl((t0 + end) / 2)}</text><text x="${W - R}" y="${H - 6}" text-anchor="end">${dl(end)}</text>`;
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
        out += `<rect x="${(x(k) - bw / 2 + slot / 2).toFixed(1)}" y="${top.toFixed(1)}" width="${bw.toFixed(1)}" height="${h.toFixed(1)}" rx="2" fill="${color}"><title>${dl(k)}: ${hf(p.v)}</title></rect>`;
      }
      return;
    }
    const pts = s.pts.map((p) => [x(p.t), y(p.v), p]);
    if (pts.length > 1) {
      const line = smoothPath(pts);
      if (list.length === 1) {
        out += `<defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${color}" stop-opacity="0.35"/><stop offset="1" stop-color="${color}" stop-opacity="0"/></linearGradient></defs>`;
        out += `<path d="${line}L${pts[pts.length - 1][0].toFixed(1)},${H - B}L${pts[0][0].toFixed(1)},${H - B}Z" fill="url(#${id})"/>`;
      }
      out += `<path d="${line}" fill="none" stroke="${color}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>`;
    }
    pts.forEach((p, j) => {
      const last = j === pts.length - 1;
      if (pts.length > 40 && !last) return;
      out += `<circle cx="${p[0].toFixed(1)}" cy="${p[1].toFixed(1)}" r="${last ? 4 : 2.8}" fill="${color}"><title>${dl(p[2].t)}: ${hf(p[2].v)}</title></circle>`;
    });
  });
  for (const v of ticks) out += pill(af(v), y(v), W);
  return `<svg class="hmc-chart" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet">${out}</svg>`;
}

function statRow(name, value) {
  return `<div class="hmc-row"><span>${name}</span><b>${value}</b></div>`;
}

// Average / range (lines) or average / total / best day (bars) for a single series.
function statsHtml(list, type, fmtv) {
  if (list.length !== 1 || !list[0].pts.length) return "";
  const v = list[0].pts.map((p) => p.v);
  const sum = v.reduce((a, b) => a + b, 0);
  const avg = sum / v.length;
  if (type === "bar") return statRow("Average", fmtv(avg)) + statRow("Total", fmtv(sum)) + statRow("Best day", fmtv(Math.max(...v)));
  return statRow("Average", fmtv(avg)) + statRow("Range (min – max)", `${fmtv(Math.min(...v))} – ${fmtv(Math.max(...v))}`) + statRow("Latest", fmtv(v[v.length - 1]));
}

// rows: hourly changes [{t, v}] -> cumulative today vs the mean cumulative day before it.
function todayModel(rows, now) {
  const today = dayStart(now);
  const hourNow = new Date(now).getHours();
  const days = new Map();
  for (const r of rows) {
    const d = dayStart(r.t);
    if (!days.has(d)) days.set(d, new Array(24).fill(0));
    days.get(d)[new Date(r.t).getHours()] += r.v;
  }
  const cum = (a) => {
    let s = 0;
    return a.map((v) => (s += v));
  };
  const prior = [...days.entries()].filter(([d]) => d < today).map(([, a]) => cum(a));
  const avg = prior.length ? Array.from({ length: 24 }, (_, h) => prior.reduce((s, c) => s + c[h], 0) / prior.length) : [];
  const t = days.has(today) ? cum(days.get(today)).slice(0, hourNow + 1) : [];
  return { today: t, avg, todayNow: t.length ? t[t.length - 1] : null, avgNow: avg.length ? avg[hourNow] : null, hourNow, days: prior.length };
}

function todaySvg(m, color, now, opts = {}) {
  const W = 640;
  const H = 220;
  const L = 8;
  const R = 54;
  const T = 12;
  const B = 24;
  if (!m.avg.length && !m.today.length) return "";
  const hiRaw = Math.max(m.avg.length ? m.avg[23] : 0, ...m.today, 1e-9);
  const hi = hiRaw * 1.08;
  const x = (h) => L + (h / 24) * (W - L - R);
  const y = (v) => T + (1 - v / hi) * (H - T - B);
  const af = opts.axisFmt || ((v) => String(Math.round(v)));
  const d = new Date(now);
  const hf = d.getHours() + d.getMinutes() / 60;
  const label = String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
  let out = "";
  const tk = niceTicks(0, hi, opts.steps);
  for (const v of tk) out += `<line class="grid" x1="${L}" x2="${W - R / 2}" y1="${y(v).toFixed(1)}" y2="${y(v).toFixed(1)}"/>`;
  out += `<text x="${L}" y="${H - 6}" text-anchor="start">00:00</text><text x="${x(hf).toFixed(1)}" y="${H - 6}" text-anchor="middle">${label}</text><text x="${W - R}" y="${H - 6}" text-anchor="end">00:00</text>`;
  out += `<line class="grid" stroke-dasharray="3 3" x1="${x(hf).toFixed(1)}" x2="${x(hf).toFixed(1)}" y1="${T}" y2="${H - B}"/>`;
  if (m.avg.length) out += `<path d="${smoothPath([[x(0), y(0)], ...m.avg.map((v, h) => [x(h + 1), y(v)])])}" fill="none" stroke="var(--secondary-text-color)" stroke-opacity="0.55" stroke-width="2.2" stroke-linecap="round"/>`;
  if (m.today.length) {
    const pts = [[x(0), y(0)], ...m.today.map((v, h) => [h === m.today.length - 1 ? x(hf) : x(h + 1), y(v)])];
    out += `<path d="${smoothPath(pts)}" fill="none" stroke="${color}" stroke-width="2.6" stroke-linecap="round"/><circle cx="${pts[pts.length - 1][0].toFixed(1)}" cy="${pts[pts.length - 1][1].toFixed(1)}" r="4.5" fill="${color}"/>`;
  }
  for (const v of tk) out += pill(af(v), y(v), W);
  return `<svg class="hmc-chart" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet">${out}</svg>`;
}

function ringSvg(score, size) {
  const r = size / 2 - 5;
  const c = 2 * Math.PI * r;
  const f = score === null ? 0 : Math.max(0, Math.min(score, 100)) / 100;
  const col = score === null ? "none" : TONE_COLOR[scoreTone(score)];
  const h = size / 2;
  return (
    `<svg viewBox="0 0 ${size} ${size}" width="${size}" height="${size}"><circle cx="${h}" cy="${h}" r="${r}" fill="none" stroke="var(--divider-color)" stroke-width="5"/>` +
    `<circle cx="${h}" cy="${h}" r="${r}" fill="none" stroke="${col}" stroke-width="5" stroke-linecap="round" stroke-dasharray="${(c * f).toFixed(1)} ${c.toFixed(1)}" transform="rotate(-90 ${h} ${h})"/>` +
    `<text x="${h}" y="${h}" dy=".35em" text-anchor="middle" class="ringtxt" style="font-size:${(size * 0.34).toFixed(0)}px">${score === null ? "" : score}</text></svg>`
  );
}

function scoreTone(s) {
  return s >= 70 ? "good" : s >= 50 ? "mid" : "bad";
}

// Weighted mean of the components that have data: duration vs target, deep+REM share, HRV vs own baseline.
function sleepScore({ dur, deep, rem, hrv, hrvBase, target }) {
  const parts = [];
  if (dur > 0) parts.push([0.6, Math.min(dur / target, 1)]);
  if (dur > 0 && isFinite(deep) && isFinite(rem)) parts.push([0.2, Math.min((deep + rem) / dur / 0.35, 1)]);
  if (isFinite(hrv) && isFinite(hrvBase) && hrvBase > 0) parts.push([0.2, Math.max(0, Math.min(hrv / hrvBase, 1))]);
  if (!parts.length) return null;
  const w = parts.reduce((a, p) => a + p[0], 0);
  return Math.round((100 * parts.reduce((a, p) => a + p[0] * p[1], 0)) / w);
}

const mean = (a) => (a.length ? a.reduce((s, v) => s + v, 0) / a.length : NaN);

// s: {dur, awake, deep, core, rem, hrv, hr} daily series [{t, v}] over ~28 days.
function sleepModel(s, now, target) {
  const by = (arr) => {
    const m = new Map((arr || []).map((p) => [dayStart(p.t), p.v]));
    m.near = (d) => (m.has(d) ? m.get(d) : m.get(dayStart(d - 43200000)));
    return m;
  };
  const dur = by(s.dur);
  const awake = by(s.awake);
  const deep = by(s.deep);
  const core = by(s.core);
  const rem = by(s.rem);
  const hrv = by(s.hrv);
  const hr = by(s.hr);
  const hrvBase = mean([...hrv.values()]);
  const hrBase = mean([...hr.values()]);
  const today = dayStart(now);
  const dayOf = (i) => {
    const d = new Date(today);
    d.setDate(d.getDate() - i);
    return d.getTime();
  };
  const scoreOf = (d) => (dur.get(d) > 0 ? sleepScore({ dur: dur.get(d), deep: deep.near(d), rem: rem.near(d), hrv: hrv.near(d), hrvBase, target }) : null);
  const week = [6, 5, 4, 3, 2, 1, 0].map((i) => ({ t: dayOf(i), score: scoreOf(dayOf(i)) }));
  const last = [...dur.keys()].filter((d) => dur.get(d) > 0).sort((a, b) => b - a)[0];
  if (last === undefined) return null;
  const d = dur.get(last);
  const tiles = [{ name: "Duration", value: shortDur(d), tone: d >= target * 0.9 ? "good" : d >= target * 0.75 ? "mid" : "bad" }];
  const hrN = hr.near(last);
  if (hrN !== undefined) tiles.push({ name: "Heart rate", value: `${Math.round(hrN)} bpm`, tone: hrN <= hrBase + 3 ? "good" : "mid" });
  const hrvN = hrv.near(last);
  if (hrvN !== undefined) tiles.push({ name: "HRV", value: `${Math.round(hrvN)} ms`, tone: hrvN >= hrvBase * 0.9 ? "good" : hrvN >= hrvBase * 0.75 ? "mid" : "bad" });
  if (deep.near(last) !== undefined) {
    const share = (deep.near(last) / d) * 100;
    tiles.push({ name: "Depth", value: `${Math.round(share)} % deep`, tone: share >= 13 ? "good" : share >= 8 ? "mid" : "bad" });
  }
  const recent = week.map((w) => dur.get(w.t)).filter((v) => v > 0);
  if (recent.length >= 3) {
    const m = mean(recent);
    const sd = Math.sqrt(mean(recent.map((v) => (v - m) * (v - m))));
    tiles.push({ name: "Regularity", value: sd < 45 ? "Good" : sd < 75 ? "Fair" : "Poor", tone: sd < 45 ? "good" : sd < 75 ? "mid" : "bad" });
  }
  const awN = awake.near(last);
  if (awN !== undefined) tiles.push({ name: "Awake", value: `${Math.round(awN)} min`, tone: awN <= 20 ? "good" : awN <= 40 ? "mid" : "bad" });
  const wk = [...dur.entries()].filter(([t, v]) => v > 0 && ![0, 6].includes(new Date(t).getDay())).map(([, v]) => v);
  const we = [...dur.entries()].filter(([t, v]) => v > 0 && [0, 6].includes(new Date(t).getDay())).map(([, v]) => v);
  const stages = [["Awake", awake.near(last), "#f08a80"], ["REM", rem.near(last), "#6bb8ff"], ["Core", core.near(last), "#4a6cf7"], ["Deep", deep.near(last), "#3b3f9e"]].filter((st) => isFinite(st[1]));
  return { score: scoreOf(last), last, tiles, week, avgWeekday: mean(wk), avgWeekend: mean(we), stages };
}

function sleepHtml(m, lang) {
  const ico = (t) => `<span class="ico ${t}">${t === "good" ? "✓" : "!"}</span>`;
  const tiles = m.tiles.map((t) => `<div class="tile"><div class="tn">${t.name}</div><div class="tv">${t.value}</div>${ico(t.tone)}</div>`).join("");
  const week = m.week
    .map((w) => `<div class="wd">${ringSvg(w.score, 44)}<div>${new Date(w.t).toLocaleDateString(lang, { weekday: "narrow" })}</div></div>`)
    .join("");
  const total = m.stages.reduce((a, st) => a + st[1], 0);
  const stages = m.stages
    .map((st) => `<div class="stage"><span style="color:${st[2]}">${st[0]}</span><b>${shortDur(st[1])}</b><i style="width:${total ? ((st[1] / total) * 100).toFixed(0) : 0}%;background:${st[2]}"></i></div>`)
    .join("");
  const avg = (name, v) => (isFinite(v) ? statRow(name, shortDur(v)) : "");
  return (
    `<div class="hmc-sleep"><div class="ringbox">${ringSvg(m.score, 92)}<div class="ringlabel">Sleep score</div></div>` +
    `<div class="tiles">${tiles}</div>` +
    (stages ? `<div class="stages">${stages}</div>` : "") +
    `<div class="week">${week}</div>` +
    `<div class="avgs">${avg("Average weekday", m.avgWeekday)}${avg("Average weekend", m.avgWeekend)}</div></div>`
  );
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

// "min–max" of a series, for the chip that replaces a delta on noisy readings.
function rangeText(series, decimals, unit, lang) {
  if (!series.length) return "";
  const vals = series.map((p) => p.v);
  const lo = fmt(Math.min(...vals), decimals, lang);
  const hi = fmt(Math.max(...vals), decimals, lang);
  return lo === hi ? "" : lo + "\u2013" + hi + unit;
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
  .hmc-chart .pill { fill: var(--secondary-background-color, rgba(255,255,255,.08)); stroke: var(--divider-color); }
  .hmc-chart .pilltxt { fill: var(--primary-text-color); font-size: 11px; }
  .hmc-tabs { display: flex; align-items: center; gap: 6px; margin-bottom: 8px; }
  .hmc-tabs .sp { flex: 1; }
  .hmc-tabs button { border: 0; border-radius: 999px; padding: 4px 12px; font-size: 13px; cursor: pointer; background: transparent; color: var(--secondary-text-color); }
  .hmc-tabs button.on { background: color-mix(in srgb, var(--primary-color) 28%, transparent); color: var(--primary-text-color); }
  .hmc-tabs button[disabled] { opacity: .3; cursor: default; }
  .hmc-stats { margin-top: 8px; border-top: 1px solid var(--divider-color); }
  .hmc-row { display: flex; justify-content: space-between; padding: 9px 0; border-bottom: 1px solid var(--divider-color); font-size: 14px; }
  .hmc-row:last-child { border-bottom: 0; }
  .hmc-row span { color: var(--secondary-text-color); }
  .hmc-cmp { display: flex; gap: 40px; margin-bottom: 6px; }
  .hmc-cmp span { display: block; font-size: 12px; color: var(--secondary-text-color); }
  .hmc-cmp b { font-size: 26px; }
  .hmc-sleep { display: grid; gap: 14px; }
  .ringbox { display: grid; justify-items: center; gap: 4px; }
  .ringlabel { font-size: 15px; font-weight: 600; }
  .ringtxt { fill: var(--primary-text-color); font-weight: 700; }
  .tiles { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
  .tile { position: relative; border-radius: 14px; padding: 10px 12px; background: var(--secondary-background-color, rgba(255,255,255,.06)); }
  .tn { font-size: 12px; color: var(--secondary-text-color); }
  .tv { font-size: 17px; font-weight: 700; margin-top: 2px; }
  .ico { position: absolute; right: 10px; top: 50%; transform: translateY(-50%); width: 22px; height: 22px; border-radius: 50%; display: grid; place-items: center; font-size: 13px; font-weight: 800; color: #111; }
  .ico.good { background: #7ccf7c; }
  .ico.mid { background: #f2c14e; }
  .ico.bad { background: #f08a80; }
  .stage { position: relative; display: flex; justify-content: space-between; padding: 6px 0; font-size: 14px; border-bottom: 1px dashed var(--divider-color); }
  .stage i { position: absolute; left: 0; bottom: -1px; height: 2px; }
  .week { display: flex; justify-content: space-between; padding: 8px 4px; border-radius: 14px; background: var(--secondary-background-color, rgba(255,255,255,.06)); }
  .wd { display: grid; justify-items: center; gap: 2px; font-size: 12px; color: var(--secondary-text-color); }
  .wd .ringtxt { font-size: 14px !important; font-weight: 500; }
`;

class HealthMetricCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.entity) throw new Error("health-metric-card: entity is required");
    this._config = Object.assign({ chart: {}, items: [] }, config);
    if (this._config.decimals === -1) delete this._config.decimals;
    if (this._config.delta) {
      this._config.delta = Object.assign({}, this._config.delta);
      if (this._config.delta.decimals === -1) delete this._config.delta.decimals;
      if (this._config.delta.unit === "auto") delete this._config.delta.unit;
    }
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
    const now = spec.end ? new Date(new Date(spec.end).getFullYear(), new Date(spec.end).getMonth(), new Date(spec.end).getDate() + 1) : new Date();
    const last = spec.end ? new Date(spec.end) : now;
    const start = new Date(last.getFullYear(), last.getMonth(), last.getDate() - (days - 1));
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
      if (stat === "change") {
        const top = bucketDaily(raw, "max");
        pts = top.map((p, i) => ({ t: p.t, v: i ? Math.max(0, p.v - top[i - 1].v) : 0 }));
      } else pts = bucketDaily(raw, stat === "reading" ? "last" : stat);
    }
    if (stat === "reading" && !spec.end) {
      const live = st ? parseFloat(st.state) : NaN;
      const lastP = pts[pts.length - 1];
      if (isFinite(live) && (!lastP || Math.abs(lastP.v - live) > 1e-9)) {
        if (lastP && dayStart(lastP.t) === dayStart(Date.now())) lastP.v = live;
        else pts.push({ t: dayStart(Date.now()), v: live });
      }
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
    const bound = (k, entity, spec) => this._series(entity, Object.assign({}, spec, { stat: k === "lo" ? "min" : "max" }));
    if (c.delta && c.delta.mode === "range") for (const k of ["lo", "hi"]) jobs.push(bound(k, c.entity, c.chart).then((s) => (this._data[k] = s)));
    c.items.forEach((it, i) => {
      if (it.mode === "now") for (const k of ["lo", "hi"]) jobs.push(bound(k, it.entity, { days: it.days || 30, scale: it.scale, source: it.source }).then((s) => (this._data[k + i] = s)));
    });
    try {
      await Promise.all(jobs);
    } catch (e) {
      /* keep whatever loaded */
    }
    this._render();
  }

  // True min/max points for a range chip, plus the live reading; falls back to the plotted series.
  _span(key, fallback, live) {
    const pts = [...(this._data["lo" + key] || []), ...(this._data["hi" + key] || [])];
    if (!pts.length) return fallback;
    return isFinite(live) ? [...pts, { v: live }] : pts;
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
    const chartMain = this._data.main || [];
    const raw = c.hero_from === "chart" ? (chartMain.length ? chartMain[chartMain.length - 1].v / scale : NaN) : st ? parseFloat(st.state) : NaN;
    const hero = isFinite(raw) ? this._formatMain(raw * scale) : { text: "\u2013", unit: "" };
    const heroHtml = hero.html || `<span class="value">${hero.text}</span><span class="unit">${hero.unit}</span>`;

    let under = "";
    const main = this._data.main || [];
    if (c.goal && isFinite(raw)) {
      under = `<div class="sub">${fmt(Math.round((raw / c.goal) * 100), 0, lang)} % Goal</div>`;
    } else if (c.delta && c.delta.mode === "range" && main.length) {
      const dec = c.delta.decimals !== undefined ? c.delta.decimals : 1;
      const unit = c.delta.unit !== undefined ? c.delta.unit : " " + (hero.unit || "");
      const rt = rangeText(this._span("", main, raw * scale), dec, unit, lang);
      if (rt) under = `<span class="chip neutral">${rt}</span>`;
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
        if (it.mode === "now") {
          const range = rangeText(this._span(String(i), s, nowVal), dec, "", lang);
          return (
            `<div class="item" style="--dot:${it.color || accent}"><div><div class="name"><span class="dot"></span>${it.name || ""}</div>` +
            `<div class="change">${now} ${unit}</div><div class="now">${range ? range + " " + unit : "&nbsp;"}</div></div></div>`
          );
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
    if (c.popup.sleep && usable(this._hass, c.popup.sleep.duration)) {
      const sec = document.createElement("div");
      sec.className = "hmc-graph";
      body.appendChild(sec);
      await this._renderSleep(c.popup.sleep, sec);
    }
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
        if (g.type === "today") await this._renderToday(g, box);
        else await this._renderGraph(g, sec, box);
      })
    );
  }

  _graphFmt(g, ents, pts) {
    const lang = this._hass.language;
    const st = this._hass.states[ents[0].entity];
    const unit = g.unit !== undefined ? g.unit : (st && st.attributes.unit_of_measurement) || "";
    if (g.format === "duration") return { fmtv: shortDur, axisFmt: (v) => fmt(v / 60, v % 60 ? 1 : 0, lang) + " h", steps: DUR_STEPS };
    const dec = g.decimals !== undefined ? g.decimals : pts.every((v) => Math.abs(v - Math.round(v)) < 0.05) ? 0 : 1;
    return { fmtv: (v) => fmt(v, dec, lang) + (unit ? " " + unit : ""), axisFmt: (v) => fmt(v, dec, lang) };
  }

  async _renderGraph(g, sec, box) {
    const c = this._config;
    const lang = this._hass.language;
    const stat = popupStat(this._hass.states, g);
    const ents = g.entities.map((e) => (typeof e === "string" ? { entity: e } : e)).filter((e) => usable(this._hass, e.entity));
    const ranges = RANGES.some((r) => r[0] === (g.days || 30)) ? RANGES : [...RANGES, [g.days, g.days + "d"]].sort((a, b) => a[0] - b[0]);
    const state = { days: g.days || 30, offset: 0 };
    const draw = async () => {
      const end = new Date(dayStart(Date.now()));
      end.setDate(end.getDate() - state.offset * state.days);
      const list = await Promise.all(
        ents.map(async (e) => {
          let pts = [];
          try {
            pts = await this._series(e.entity, { days: state.days, stat, scale: g.scale, end: end.getTime() });
          } catch (err) {
            /* leave empty */
          }
          return { name: e.name, color: e.color || (ents.length === 1 ? c.color : undefined), pts: g.type === "bar" && stat !== "reading" ? pts : collapseRuns(pts) };
        })
      );
      const { fmtv, axisFmt, steps } = this._graphFmt(g, ents, list.flatMap((s) => s.pts.map((p) => p.v)));
      const tabs =
        `<div class="hmc-tabs">${ranges.map((r) => `<button data-days="${r[0]}" class="${r[0] === state.days ? "on" : ""}">${r[1]}</button>`).join("")}` +
        `<span class="sp"></span><button data-nav="1" aria-label="Earlier">‹</button><button data-nav="-1" aria-label="Later" ${state.offset === 0 ? "disabled" : ""}>›</button></div>`;
      const svg = chartSvg(list, g.type || "line", state.days, !!g.stacked, lang, { end: end.getTime(), fmt: fmtv, axisFmt, steps });
      const legend =
        list.length > 1
          ? `<div class="hmc-legend">${list.map((s, i) => `<span><i style="background:${s.color || PALETTE[i % PALETTE.length]}"></i>${s.name}</span>`).join("")}</div>`
          : "";
      box.innerHTML = tabs + (svg ? svg + legend + `<div class="hmc-stats">${statsHtml(list, g.type || "line", fmtv)}</div>` : `<div class="empty">No data in this period</div>`);
    };
    sec.addEventListener("click", (e) => {
      const b = e.target.closest && e.target.closest("button");
      if (!b || b.disabled) return;
      if (b.dataset.days) {
        state.days = Number(b.dataset.days);
        state.offset = 0;
      } else if (b.dataset.nav) state.offset = Math.max(0, state.offset + Number(b.dataset.nav));
      draw();
    });
    await draw();
  }

  async _renderToday(g, box) {
    const c = this._config;
    const lang = this._hass.language;
    const e = typeof g.entities[0] === "string" ? g.entities[0] : g.entities[0].entity;
    let rows = [];
    try {
      const start = new Date();
      start.setDate(start.getDate() - (g.days || 14));
      const res = await this._hass.callWS({
        type: "recorder/statistics_during_period",
        start_time: start.toISOString(),
        statistic_ids: [e],
        period: "hour",
        types: ["change"],
      });
      rows = (res[e] || []).filter((r) => r.change !== null && r.change !== undefined).map((r) => ({ t: typeof r.start === "number" ? r.start : Date.parse(r.start), v: r.change * (g.scale || 1) }));
    } catch (err) {
      /* leave empty */
    }
    const now = Date.now();
    const m = todayModel(rows, now);
    const { fmtv, axisFmt, steps } = this._graphFmt(g, [{ entity: e }], [...m.today, ...m.avg]);
    const svg = todaySvg(m, c.color || "var(--primary-color)", now, { axisFmt, steps });
    if (!svg) {
      box.innerHTML = `<div class="empty">No data yet</div>`;
      return;
    }
    box.innerHTML =
      `<div class="hmc-cmp"><div><span style="color:${c.color || "var(--primary-color)"}">● Today</span><b style="color:${c.color || "var(--primary-color)"}">${m.todayNow === null ? "–" : fmtv(m.todayNow)}</b></div>` +
      `<div><span>● Average</span><b>${m.avgNow === null ? "–" : fmtv(m.avgNow)}</b></div></div>` +
      svg;
  }

  async _renderSleep(cfg, sec) {
    const lang = this._hass.language;
    const get = async (key, stat = "reading") => {
      if (!cfg[key] || !usable(this._hass, cfg[key])) return [];
      try {
        const s = await this._series(cfg[key], { days: 28, stat });
        return stat === "reading" ? collapseRuns(s) : s;
      } catch (err) {
        return [];
      }
    };
    const [dur, awake, deep, core, rem, hrv, hr] = await Promise.all([get("duration"), get("awake"), get("deep"), get("core"), get("rem"), get("hrv", "mean"), get("hr", "mean")]);
    const m = sleepModel({ dur, awake, deep, core, rem, hrv, hr }, Date.now(), cfg.target || 450);
    sec.innerHTML = m ? sleepHtml(m, lang) : `<div class="empty">No sleep data yet</div>`;
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
  module.exports = { usable, popupStat, chartSvg, statsHtml, todayModel, todaySvg, sleepScore, sleepModel, sleepHtml, smoothPath, shortDur, readingsFromMinMax, collapseRuns, ratioSeries, durationHtml, bucketDaily, computeDelta, rangeText, deltaTone, deltaDir, signed, fmt, sparkSvg, dayStart };
}
