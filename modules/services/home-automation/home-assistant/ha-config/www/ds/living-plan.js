import { sheet } from "./tokens.js?v=12";
import { esc } from "./dom.js?v=12";
import { moonIllumination, moonPosition, planAngle } from "./astro.js?v=12";

const rad = Math.PI / 180;
const MX = 44;
const MT = 56;
const MB = 36;
const PAD = 30;
const DOOR_ICON = /door/;

export const skyBand = (el) => (el > 10 ? "day" : el > 0 ? "golden" : el > -6 ? "twilight" : "night");

// Plan up = south, left = east: a bearing maps to the ray from the plan centre to the ring around it.
export function ringPos(azimuth, [W, H]) {
  const a = planAngle(azimuth) * rad;
  const dx = Math.sin(a);
  const dy = -Math.cos(a);
  const sw = W + 2 * MX;
  const sh = H + MT + MB;
  const cx = MX + W / 2;
  const cy = MT + H / 2;
  const tx = dx > 0 ? (sw - PAD - cx) / dx : dx < 0 ? (cx - PAD) / -dx : Infinity;
  const ty = dy > 0 ? (sh - PAD - cy) / dy : dy < 0 ? (cy - PAD) / -dy : Infinity;
  const t = Math.min(tx, ty);
  return [((cx + dx * t) / sw) * 100, ((cy + dy * t) / sh) * 100];
}

export function beamPoints(x, w, azimuth, elevation, { fan = 1, reach = 22, max = 165 } = {}) {
  const a = planAngle(azimuth) * rad;
  const sx = Math.sin(a);
  const sy = -Math.cos(a);
  if (elevation <= 0 || sy >= -0.15) return null;
  const len = Math.min(max, reach / Math.tan(Math.max(elevation, 1.5) * rad));
  const sh = Math.max(-2.5, Math.min(2.5, sx / sy)) * len;
  const y = 6;
  const w2 = (w * fan) / 2;
  return `${x - w / 2},${y} ${x + w / 2},${y} ${x + w2 + sh},${y + len} ${x - w2 + sh},${y + len}`;
}

const SUN_BEAM = { fan: 2.6, reach: 40, max: 340 };
const MOON_BEAM = { fan: 1, reach: 40, max: 200 };

// Unit tangent and inward normal of the plan edge nearest to pos.
export function wallFrame([x, y], [W, H]) {
  const d = [y, H - y, x, W - x];
  return [[1, 0, 0, 1], [1, 0, 0, -1], [0, 1, 1, 0], [0, 1, -1, 0]][d.indexOf(Math.min(...d))];
}

const f1 = (v) => v.toFixed(1);

export function openingSvg(b, size) {
  const [x, y] = b.pos;
  const [tx, ty, nx, ny] = wallFrame(b.pos, size);
  const L = DOOR_ICON.test(b.icon) ? 40 : 44;
  const tone = b.tone === "open" || b.tone === "alert" ? b.tone : b.tone === "dead" ? "dead" : "ok";
  const on = tone === "open" || tone === "alert";
  const P = (u, v) => `${f1(x + tx * u + nx * v)} ${f1(y + ty * u + ny * v)}`;
  const [hx, hy] = P(-L / 2, 0).split(" ");
  const line = (cls, u1, v1, u2, v2) => `<path class="${cls}" d="M${P(u1, v1)}L${P(u2, v2)}"/>`;
  const h = L / 2;
  let body;
  if (DOOR_ICON.test(b.icon)) {
    const sweep = nx * ty - ny * tx > 0 ? 1 : 0;
    const arc = `A${L} ${L} 0 0 ${sweep} ${P(h, 0)}`;
    body = on
      ? `<path class="sector" d="M${P(-h, 0)}L${P(-h, L)}${arc}Z"/>${line("leaf", -h, 0, -h, L)}<path class="arc" d="M${P(-h, L)}${arc}"/>${line("jamb", -h, 0, h, 0)}<circle class="hinge" cx="${hx}" cy="${hy}" r="2.4"/>`
      : `${line("jamb", -h, 0, h, 0)}<circle class="hinge" cx="${hx}" cy="${hy}" r="2"/>`;
  } else {
    const g = L * 0.28;
    body = on
      ? `${line("halo", -h, 0, h, 0)}${line("sash", -h, 0, -h + g, 0)}${line("sash", h - g, 0, h, 0)}${line("tick", -h + g, -4, -h + g, 4)}${line("tick", h - g, -4, h - g, 4)}`
      : `${line("pane", -h, -2.2, h, -2.2)}${line("pane", -h, 2.2, h, 2.2)}`;
  }
  return `<g class="op ${DOOR_ICON.test(b.icon) ? "door" : "win"} ${tone}">${body}</g>`;
}

const smooth = (x, a, b) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};

function moonPath(m) {
  const lit = m.waxing ? 1 : 0;
  const term = m.fraction < 0.5 ? 1 - lit : lit;
  return `M0 -17A17 17 0 0 ${lit} 0 17A${(Math.abs(1 - 2 * m.fraction) * 17).toFixed(2)} 17 0 0 ${term} 0 -17Z`;
}

export function livingHtml(m, cfg, hass, now = new Date()) {
  const [W, H] = cfg.size || [730, 620];
  const sw = W + 2 * MX;
  const sh = H + MT + MB;
  const pct = (v, t) => ((v / t) * 100).toFixed(3) + "%";
  const sun = hass.states["sun.sun"];
  const el = sun ? Number(sun.attributes.elevation) : NaN;
  const az = sun ? Number(sun.attributes.azimuth) : NaN;
  const known = Number.isFinite(el) && Number.isFinite(az);
  const band = known ? skyBand(el) : "day";
  const parts = [];
  const lat = hass.config && hass.config.latitude;
  const lon = hass.config && hass.config.longitude;
  const rays = Array.from({ length: 12 }, (_, i) => `<path d="M-2.6 -17.5L0 -${i % 2 ? 24 : 29}L2.6 -17.5Z" transform="rotate(${i * 30})"/>`).join("");
  if (known && el >= 0) {
    const [x, y] = ringPos(az, [W, H]);
    parts.push(
      `<svg class="orb" viewBox="-32 -32 64 64" style="left:${x.toFixed(2)}%;top:${y.toFixed(2)}%" aria-hidden="true"><defs><radialGradient id="lph"><stop offset="0.35" style="stop-color:var(--ds-sun-halo)" stop-opacity="0.7"/><stop offset="1" style="stop-color:var(--ds-sun-halo)" stop-opacity="0"/></radialGradient><radialGradient id="lpd" cx="0.4" cy="0.38" r="0.7"><stop offset="0" style="stop-color:var(--ds-sun-core)"/><stop offset="0.5" style="stop-color:var(--ds-sun)"/><stop offset="1" style="stop-color:var(--ds-sun-edge)"/></radialGradient></defs><circle r="32" fill="url(#lph)"/><g class="rays">${rays}</g><circle r="13" fill="url(#lpd)"/></svg>`
    );
  }
  let moonUp = null;
  if (lat != null && lon != null) {
    const mp = moonPosition(now, lat, lon);
    if (mp.altitude >= 0) {
      const [x, y] = ringPos(mp.azimuth, [W, H]);
      const ill = moonIllumination(now);
      moonUp = { mp, ill };
      parts.push(
        `<svg class="moon ${known && el > 0 ? "dim" : ""}" viewBox="-20 -20 40 40" style="left:${x.toFixed(2)}%;top:${y.toFixed(2)}%"><circle r="17" class="dk"/><path d="${moonPath(ill)}" class="lt"/></svg>`
      );
    }
  }
  const openings = m.rooms.flatMap((r) => r.badges.filter((b) => b.pos && b.kind === "opening"));
  const south = [...openings, ...(cfg.windows || []).map((pos) => ({ pos, icon: "window", tone: "ok" }))].filter((b) => b.pos[1] < 20);
  const width = (b) => (DOOR_ICON.test(b.icon) ? 36 : 24);
  const gold = band === "golden";
  let beams = [];
  let color = "--ds-beam";
  let peak = 0;
  if (known && el > 0) {
    beams = south.map((b) => beamPoints(b.pos[0], width(b), az, el, SUN_BEAM)).filter(Boolean);
    color = gold ? "--ds-beam-golden" : "--ds-beam";
    peak = (gold ? 0.24 : 0.3) * (0.5 + 0.5 * smooth(el, 0, 8));
  } else if (moonUp) {
    beams = south.map((b) => beamPoints(b.pos[0], width(b), moonUp.mp.azimuth, moonUp.mp.altitude, MOON_BEAM)).filter(Boolean);
    color = "--ds-moon-beam";
    peak = 0.3 * (0.35 + 0.65 * smooth(moonUp.mp.altitude, 0, 20)) * (0.15 + 0.85 * moonUp.ill.fraction);
  }
  const svg = beams.length
    ? `<svg class="beams ${color === "--ds-moon-beam" ? "moonlit" : ""}" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" aria-hidden="true"><defs><linearGradient id="lpb" x1="0" y1="0" x2="0" y2="1"><stop offset="0" style="stop-color:var(${color})" stop-opacity="${peak.toFixed(3)}"/><stop offset="1" style="stop-color:var(${color})" stop-opacity="0"/></linearGradient><filter id="lpf" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="4"/></filter><clipPath id="lpc"><rect width="${W}" height="${H}"/></clipPath></defs><g clip-path="url(#lpc)" filter="url(#lpf)">${beams.map((p) => `<polygon fill="url(#lpb)" points="${p}"/>`).join("")}</g></svg>`
    : "";
  const marks = `<svg class="ops" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" aria-hidden="true">${south.map((b) => openingSvg(b, [W, H])).join("")}${openings.filter((b) => b.pos[1] >= 20).map((b) => openingSvg(b, [W, H])).join("")}</svg>`;
  const rooms = m.rooms
    .map((r) => {
      const [x, y, w, h] = r.rect;
      const open = r.badges.filter((b) => b.kind === "opening" && (b.tone === "open" || b.tone === "alert")).length;
      const label = [r.name, r.lit ? "lights on" : "", r.occupied ? "occupied" : "", open ? `${open} open` : ""].filter(Boolean).join(", ");
      const glow = r.lit ? `--glow:${Math.round(10 + 22 * r.glow)}%;` : "";
      return `<button class="room ${r.occupied ? "occ" : ""} ${r.lit ? "lit" : ""}" data-room="${esc(r.name)}" aria-label="${esc(label)}" style="${glow}left:${pct(x, W)};top:${pct(y, H)};width:${pct(w, W)};height:${pct(h, H)}"><div class="nm">${r.short ? `<span class="f">${esc(r.name)}</span><span class="s">${esc(r.short)}</span>` : esc(r.name)}${r.occupied ? '<span class="dot"></span>' : ""}</div></button>`;
    })
    .join("");
  const image = cfg.image;
  return `<div class="stage band-${band}" style="aspect-ratio:${sw}/${sh}"><div class="sky"></div>${parts.join("")}<div class="plan img" style="left:${pct(MX, sw)};top:${pct(MT, sh)};width:${pct(W, sw)};height:${pct(H, sh)};${image ? `--img:url(${esc(image)})` : ""}">${svg}${rooms}${marks}</div></div><div class="legend"><span><i class="k lit"></i>Lights on</span><span><i class="k occ"></i>Occupied</span><span><svg class="lk op door open" viewBox="0 0 16 16" aria-hidden="true"><path class="sector" d="M2 14V2A12 12 0 0 1 14 14Z"/><path class="leaf" d="M2 14V2"/><path class="jamb" d="M2 14H14"/></svg><svg class="lk op win open" viewBox="0 0 16 16" aria-hidden="true"><path class="halo" d="M1 8H15"/><path class="sash" d="M1 8H4.5M11.5 8H15"/></svg>Open</span><span><svg class="lk op door alert" viewBox="0 0 16 16" aria-hidden="true"><path class="sector" d="M2 14V2A12 12 0 0 1 14 14Z"/><path class="leaf" d="M2 14V2"/><path class="jamb" d="M2 14H14"/></svg>Open while armed</span><span><svg class="lk op door ok" viewBox="0 0 16 16" aria-hidden="true"><path class="sector" d="M2 14V2A12 12 0 0 1 14 14Z"/><path class="leaf" d="M2 14V2"/><path class="jamb" d="M2 14H14"/></svg>Closed</span><span>Tap a room for details</span></div>`;
}

export const livingSheet = sheet(`
  :host { --ds-sun-core: #FFF4B8; --ds-sun: #FFD23F; --ds-sun-edge: #FF9A1F; --ds-sun-ray: #FFB020; --ds-sun-halo: #FFC94D; --ds-beam: #FFC53D; --ds-beam-golden: #FF9E2C; --ds-moon: #E6EEFF; --ds-moon-dark: #6C7BA3; --ds-moon-beam: #8EA6E6; }
  .stage { position: relative; width: 100%; container: stage / inline-size; overflow: hidden; border-radius: var(--ds-radius-tile); }
  .sky { position: absolute; inset: 0; }
  .band-night .sky { background: linear-gradient(color-mix(in srgb, var(--primary-color) 26%, var(--card-background-color)), color-mix(in srgb, var(--primary-color) 10%, var(--card-background-color))); }
  .band-twilight .sky { background: linear-gradient(color-mix(in srgb, var(--primary-color) 18%, var(--card-background-color)), color-mix(in srgb, var(--warning-color) 22%, var(--card-background-color))); }
  .band-golden .sky { background: linear-gradient(color-mix(in srgb, var(--warning-color) 30%, var(--card-background-color)), color-mix(in srgb, var(--warning-color) 10%, var(--card-background-color))); }
  .band-day .sky { background: linear-gradient(color-mix(in srgb, var(--primary-color) 12%, var(--card-background-color)), color-mix(in srgb, var(--primary-color) 3%, var(--card-background-color))); }
  .stage .plan { position: absolute; }
  .orb { position: absolute; width: clamp(40px, 9cqw, 64px); transform: translate(-50%, -50%); pointer-events: none; overflow: visible; }
  .orb .rays path { fill: var(--ds-sun-ray); }
  .orb .rays { animation: spin 90s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .moon { position: absolute; width: clamp(18px, 5.5cqw, 36px); transform: translate(-50%, -50%); pointer-events: none; filter: drop-shadow(0 0 4px color-mix(in srgb, var(--ds-moon) 55%, transparent)); }
  .moon.dim { opacity: 0.5; }
  .moon .dk { fill: var(--ds-moon-dark); stroke: color-mix(in srgb, var(--ds-moon) 45%, transparent); stroke-width: 1; }
  .moon .lt { fill: var(--ds-moon); }
  .beams { position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; animation: drift 6s ease-in-out infinite alternate; }
  @keyframes drift { to { opacity: 0.75; } }
  .stage .room { font: inherit; color: inherit; text-align: left; cursor: pointer; touch-action: manipulation; overflow: visible; }
  .stage .room::after { content: ""; position: absolute; left: 50%; top: 50%; width: max(100%, var(--ds-touch)); height: max(100%, var(--ds-touch)); transform: translate(-50%, -50%); }
  .stage .room:focus-visible { outline: 2px solid var(--primary-color); outline-offset: -2px; }
  .ops { position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; overflow: visible; }
  .op path { fill: none; stroke: var(--c); stroke-linecap: round; vector-effect: non-scaling-stroke; }
  .op { --c: var(--secondary-text-color); }
  .op.open { --c: var(--warning-color); }
  .op.alert { --c: var(--error-color); }
  .op.ok { opacity: 0.55; }
  .op.dead { opacity: 0.3; }
  .op.dead path { stroke-dasharray: 2 3; }
  .op .jamb, .op .pane { stroke-width: 2px; }
  .op.open .jamb, .op.alert .jamb { stroke-width: 2px; opacity: 0.55; }
  .op .leaf { stroke-width: clamp(2.5px, 0.5cqw, 4px); }
  .op .arc { stroke-width: 1.5px; stroke-dasharray: 3 3; opacity: 0.8; }
  .op .sector { fill: color-mix(in srgb, var(--c) 22%, transparent); stroke: none; }
  .op .halo { stroke-width: clamp(10px, 1.6cqw, 14px); opacity: 0.35; }
  .op .sash { stroke-width: clamp(3.5px, 0.7cqw, 6px); }
  .op .tick { stroke-width: 2px; }
  .op .hinge { fill: var(--c); }
  .lk { display: inline-block; width: 16px; height: 16px; margin-right: 4px; vertical-align: -4px; overflow: visible; }
  .lk .leaf, .lk .jamb, .lk .halo, .lk .sash { stroke-width: 2px; }
  .lk .halo { stroke-width: 6px; }
  .lk.ok { opacity: 0.7; }
  .stage .plan.img .room.lit { background: none; }
  .stage .room::before { content: ""; position: absolute; inset: 0; opacity: 0; pointer-events: none; transition: opacity 300ms ease;
    background: radial-gradient(ellipse at 50% 45%, color-mix(in srgb, var(--state-light-active-color) calc(var(--glow, 10%) + 8%), transparent), color-mix(in srgb, var(--state-light-active-color) var(--glow, 10%), transparent)); }
  .stage .room.lit::before { opacity: 1; }
  .stage .nm { position: relative; display: block; white-space: normal; overflow: visible; text-overflow: clip; overflow-wrap: anywhere; line-height: 1.15; }
  .stage .nm .s { display: none; }
  .stage .dot { animation: ring 3.2s ease-out infinite; }
  @keyframes ring { from { box-shadow: 0 0 0 0 color-mix(in srgb, var(--primary-color) 35%, transparent); } to { box-shadow: 0 0 0 6px transparent; } }
  @container room (max-width: 40px) { .stage .nm { font-size: 7px; } }
  @container stage (max-width: 560px) { .stage .room { padding: 2px 1px 2px 2px; } .stage .nm .f { display: none; } .stage .nm .s { display: inline; } }
  @media (prefers-reduced-motion: reduce) { .beams, .stage .dot, .orb .rays { animation: none; } .stage .room::before { transition: none; } }
`);
