import { sheet } from "./tokens.js?v=10";
import { esc } from "./dom.js?v=10";
import { moonIllumination, moonPosition, planAngle } from "./astro.js?v=10";

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

export function beamPoints(x, w, azimuth, elevation) {
  const a = planAngle(azimuth) * rad;
  const sx = Math.sin(a);
  const sy = -Math.cos(a);
  if (elevation <= 0 || sy >= -0.15) return null;
  const len = Math.min(165, 22 / Math.tan(Math.max(elevation, 1.5) * rad));
  const sh = Math.max(-2.5, Math.min(2.5, sx / sy)) * len;
  const y = 6;
  return `${x - w / 2},${y} ${x + w / 2},${y} ${x + w / 2 + sh},${y + len} ${x - w / 2 + sh},${y + len}`;
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
  if (known && el >= 0) {
    const [x, y] = ringPos(az, [W, H]);
    parts.push(`<i class="orb" style="left:${x.toFixed(2)}%;top:${y.toFixed(2)}%"></i>`);
  }
  if (lat != null && lon != null) {
    const mp = moonPosition(now, lat, lon);
    if (mp.altitude >= 0) {
      const [x, y] = ringPos(mp.azimuth, [W, H]);
      const ill = moonIllumination(now);
      parts.push(
        `<svg class="moon ${known && el > 0 ? "dim" : ""}" viewBox="-20 -20 40 40" style="left:${x.toFixed(2)}%;top:${y.toFixed(2)}%"><circle r="17" class="dk"/><path d="${moonPath(ill)}" class="lt"/></svg>`
      );
    }
  }
  const openings = m.rooms.flatMap((r) => r.badges.filter((b) => b.pos && b.kind === "opening"));
  const beams = known
    ? openings
        .filter((b) => b.pos[1] < 20)
        .map((b) => beamPoints(b.pos[0], DOOR_ICON.test(b.icon) ? 36 : 24, az, el))
        .filter(Boolean)
    : [];
  const gold = band === "golden";
  const peak = (gold ? 0.2 : 0.28) * (0.5 + 0.5 * smooth(el, 0, 8));
  const svg = beams.length
    ? `<svg class="beams" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" aria-hidden="true"><defs><linearGradient id="lpb" x1="0" y1="0" x2="0" y2="1"><stop offset="0" style="stop-color:var(${gold ? "--ds-beam-golden" : "--ds-beam"})" stop-opacity="${peak.toFixed(3)}"/><stop offset="1" style="stop-color:var(${gold ? "--ds-beam-golden" : "--ds-beam"})" stop-opacity="0"/></linearGradient><filter id="lpf" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="4"/></filter><clipPath id="lpc"><rect width="${W}" height="${H}"/></clipPath></defs><g clip-path="url(#lpc)" filter="url(#lpf)">${beams.map((p) => `<polygon fill="url(#lpb)" points="${p}"/>`).join("")}</g></svg>`
    : "";
  const marks = openings
    .map((b) => `<i class="mk ${b.tone}" title="${esc(b.name)}" style="left:${pct(b.pos[0], W)};top:${pct(b.pos[1], H)}"></i>`)
    .join("");
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
  return `<div class="stage band-${band}" style="aspect-ratio:${sw}/${sh}"><div class="sky"></div>${parts.join("")}<div class="plan img" style="left:${pct(MX, sw)};top:${pct(MT, sh)};width:${pct(W, sw)};height:${pct(H, sh)};${image ? `--img:url(${esc(image)})` : ""}">${svg}${rooms}${marks}</div></div><div class="legend"><span><i class="k lit"></i>Lights on</span><span><i class="k occ"></i>Occupied</span><span><i class="k open"></i>Open</span><span>Tap a room for details</span></div>`;
}

export const livingSheet = sheet(`
  :host { --ds-sun: #FFF1B8; --ds-sun-halo: #FFE58A; --ds-moon: #E6EEFF; --ds-moon-dark: #6C7BA3; --ds-beam: #FFFBEF; --ds-beam-golden: #FFE3B0; }
  .stage { position: relative; width: 100%; container: stage / inline-size; overflow: hidden; border-radius: var(--ds-radius-tile); }
  .sky { position: absolute; inset: 0; }
  .band-night .sky { background: linear-gradient(color-mix(in srgb, var(--primary-color) 26%, var(--card-background-color)), color-mix(in srgb, var(--primary-color) 10%, var(--card-background-color))); }
  .band-twilight .sky { background: linear-gradient(color-mix(in srgb, var(--primary-color) 18%, var(--card-background-color)), color-mix(in srgb, var(--warning-color) 22%, var(--card-background-color))); }
  .band-golden .sky { background: linear-gradient(color-mix(in srgb, var(--warning-color) 30%, var(--card-background-color)), color-mix(in srgb, var(--warning-color) 10%, var(--card-background-color))); }
  .band-day .sky { background: linear-gradient(color-mix(in srgb, var(--primary-color) 12%, var(--card-background-color)), color-mix(in srgb, var(--primary-color) 3%, var(--card-background-color))); }
  .stage .plan { position: absolute; }
  .orb { position: absolute; width: clamp(18px, 6cqw, 40px); aspect-ratio: 1; border-radius: 50%; transform: translate(-50%, -50%); pointer-events: none; background: var(--ds-sun); border: 1px solid color-mix(in srgb, var(--primary-text-color) 18%, transparent); box-shadow: 0 0 3cqw 1cqw color-mix(in srgb, var(--ds-sun-halo) 60%, transparent); }
  .moon { position: absolute; width: clamp(18px, 5.5cqw, 36px); transform: translate(-50%, -50%); pointer-events: none; filter: drop-shadow(0 0 4px color-mix(in srgb, var(--ds-moon) 55%, transparent)); }
  .moon.dim { opacity: 0.5; }
  .moon .dk { fill: var(--ds-moon-dark); stroke: color-mix(in srgb, var(--ds-moon) 45%, transparent); stroke-width: 1; }
  .moon .lt { fill: var(--ds-moon); }
  .beams { position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; animation: drift 6s ease-in-out infinite alternate; }
  @keyframes drift { to { opacity: 0.75; } }
  .stage .room { font: inherit; color: inherit; text-align: left; cursor: pointer; touch-action: manipulation; overflow: visible; }
  .stage .room::after { content: ""; position: absolute; left: 50%; top: 50%; width: max(100%, var(--ds-touch)); height: max(100%, var(--ds-touch)); transform: translate(-50%, -50%); }
  .stage .room:focus-visible { outline: 2px solid var(--primary-color); outline-offset: -2px; }
  .mk { position: absolute; width: 10px; height: 10px; transform: translate(-50%, -50%); border-radius: 50%; pointer-events: none; background: var(--secondary-text-color); opacity: 0.5; }
  .mk.open { background: var(--warning-color); opacity: 1; box-shadow: 0 0 0 3px color-mix(in srgb, var(--warning-color) 35%, transparent); }
  .mk.alert { background: var(--error-color); opacity: 1; box-shadow: 0 0 0 3px color-mix(in srgb, var(--error-color) 35%, transparent); }
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
  @media (prefers-reduced-motion: reduce) { .beams, .stage .dot { animation: none; } .stage .room::before { transition: none; } }
`);
