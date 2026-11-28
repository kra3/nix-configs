const rad = Math.PI / 180;
const OBL = rad * 23.4397;

const days = (date) => date.getTime() / 864e5 - 0.5 + 2440588 - 2451545;
const rightAscension = (l, b) => Math.atan2(Math.sin(l) * Math.cos(OBL) - Math.tan(b) * Math.sin(OBL), Math.cos(l));
const declination = (l, b) => Math.asin(Math.sin(b) * Math.cos(OBL) + Math.cos(b) * Math.sin(OBL) * Math.sin(l));

function sunCoords(d) {
  const M = rad * (357.5291 + 0.98560028 * d);
  const C = rad * (1.9148 * Math.sin(M) + 0.02 * Math.sin(2 * M) + 0.0003 * Math.sin(3 * M));
  const L = M + C + rad * 102.9372 + Math.PI;
  return { dec: declination(L, 0), ra: rightAscension(L, 0) };
}

function horizontal(c, d, lat, lon) {
  const H = rad * (280.16 + 360.9856235 * d) + rad * lon - c.ra;
  const p = rad * lat;
  const south = Math.atan2(Math.sin(H), Math.cos(H) * Math.sin(p) - Math.tan(c.dec) * Math.cos(p));
  return {
    azimuth: (south / rad + 180 + 360) % 360,
    altitude: Math.asin(Math.sin(p) * Math.sin(c.dec) + Math.cos(p) * Math.cos(c.dec) * Math.cos(H)) / rad,
  };
}

function moonCoords(d) {
  const L = rad * (218.316 + 13.176396 * d);
  const M = rad * (134.963 + 13.064993 * d);
  const F = rad * (93.272 + 13.22935 * d);
  const l = L + rad * 6.289 * Math.sin(M);
  const b = rad * 5.128 * Math.sin(F);
  return { ra: rightAscension(l, b), dec: declination(l, b), dist: 385001 - 20905 * Math.cos(M) };
}

export function sunPosition(date, lat, lon) {
  const d = days(date);
  return horizontal(sunCoords(d), d, lat, lon);
}

export function moonPosition(date, lat, lon) {
  const d = days(date);
  return horizontal(moonCoords(d), d, lat, lon);
}

export function moonIllumination(date) {
  const d = days(date);
  const s = sunCoords(d);
  const m = moonCoords(d);
  const phi = Math.acos(
    Math.sin(s.dec) * Math.sin(m.dec) + Math.cos(s.dec) * Math.cos(m.dec) * Math.cos(s.ra - m.ra),
  );
  const inc = Math.atan2(149598000 * Math.sin(phi), m.dist - 149598000 * Math.cos(phi));
  const angle = Math.atan2(
    Math.cos(s.dec) * Math.sin(s.ra - m.ra),
    Math.sin(s.dec) * Math.cos(m.dec) - Math.cos(s.dec) * Math.sin(m.dec) * Math.cos(s.ra - m.ra),
  );
  const phase = 0.5 + (0.5 * inc * (angle < 0 ? -1 : 1)) / Math.PI;
  return { fraction: (1 + Math.cos(inc)) / 2, waxing: phase < 0.5 };
}

export const planAngle = (azimuth) => (azimuth + 180) % 360;
