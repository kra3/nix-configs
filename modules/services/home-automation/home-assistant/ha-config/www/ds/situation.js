const HOUR = 36e5;

export function timeOfDay(now, sunElevation, sunsetDate) {
  const h = now.getHours();
  if (h < 5) return "night";
  if (sunsetDate instanceof Date && !isNaN(sunsetDate)) {
    if (now >= new Date(sunsetDate.getTime() + 2 * HOUR)) return "night";
    if (now >= new Date(sunsetDate.getTime() - HOUR)) return "evening";
  } else if (h >= 12 && typeof sunElevation === "number") {
    if (sunElevation < -6) return "night";
    if (sunElevation < 10) return "evening";
  }
  return h < 10 ? "morning" : "day";
}

const isHome = (p) => !!p && p.state === "home";
const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
const list = (a) => (a.length > 1 ? `${a.slice(0, -1).join(", ")} and ${a[a.length - 1]}` : a[0]);
const arr = (a) => (Array.isArray(a) ? a : null);

function viewerState(s) {
  const p = s.people[s.viewer];
  if (!p || isHome(p)) return "home";
  if (p.arriving) return "arriving";
  if (p.justLeft) return "left";
  return "away";
}

const othersOut = (s) => Object.keys(s.people).filter((k) => k !== s.viewer && !isHome(s.people[k]));
const homeNames = (s) => Object.keys(s.people).filter((k) => isHome(s.people[k])).map(cap);
const anyHome = (s) => homeNames(s).length > 0;

function personClause(k, p) {
  const n = cap(k);
  if (typeof p.eta === "number") return `${n} is ≈ ${Math.round(p.eta)} min from home`;
  if (p.arriving) return `${n} is arriving`;
  if (p.justLeft) return `${n} just left`;
  return `${n} is away`;
}

const clauses = {
  openings: (s) => {
    const o = arr(s.openings);
    return o && o.length ? `${list(o)} ${o.length > 1 ? "are" : "is"} open` : null;
  },
  lights: (s) => {
    const l = arr(s.lightsOn);
    return l && l.length ? `lights on in ${list(l)}` : null;
  },
  attention: (s) => {
    const a = arr(s.attention);
    return a && a.length ? `${list(a.slice(0, 2))}${a.length > 2 ? ` and ${a.length - 2} more` : ""} need${a.length === 1 ? "s" : ""} attention` : null;
  },
  media: (s) => (s.media && s.media.name ? (s.media.title ? `${s.media.title} is playing on ${s.media.name}` : `${s.media.name} is playing`) : null),
  laundry: (s) => {
    const l = s.laundry;
    if (!l) return null;
    const run = arr(l.running) || [];
    const done = arr(l.done) || [];
    return [...run.map((n) => `${n} is running`), ...done.map((n) => `${n} is done`)].join(", ") || null;
  },
  others: (s) => othersOut(s).map((k) => personClause(k, s.people[k])).join(", ") || null,
};

const sentence = (parts) => {
  const t = parts.filter(Boolean).join(", ");
  return t ? `${cap(t)}.` : "";
};

const allOff = (s) => arr(s.lightsOn) && arr(s.openings) && !s.lightsOn.length && !s.openings.length;

const HEADLINES = {
  guest: (s) => sentence(["Make yourself at home", clauses.lights(s)]),
  "away-empty": (s) =>
    sentence(["Home is empty", clauses.openings(s), clauses.lights(s), allOff(s) ? "everything is off" : null, clauses.attention(s)]),
  "away-occupied": (s) => {
    const n = homeNames(s);
    return sentence([`${list(n)} ${n.length > 1 ? "are" : "is"} home`, clauses.lights(s), clauses.media(s), clauses.openings(s)]);
  },
  arriving: (s) => {
    const p = s.people[s.viewer];
    const n = homeNames(s);
    return sentence([
      typeof p.eta === "number" ? `You’re ≈ ${Math.round(p.eta)} min away` : "You’re arriving",
      n.length ? `${list(n)} ${n.length > 1 ? "are" : "is"} home` : null,
      clauses.openings(s),
    ]);
  },
  leaving: (s) => sentence(["You just left", clauses.openings(s), clauses.lights(s), allOff(s) ? "everything is off" : null]),
};

const general = (s, lead) =>
  sentence([lead, clauses.others(s), clauses.laundry(s), clauses.media(s), clauses.openings(s), clauses.lights(s), clauses.attention(s)]);

const LEAD = { morning: "Good morning", day: null, evening: "Good evening", night: "All quiet" };

const RULES = [
  { key: "guest", when: (s) => s.viewer === "guest" || !!s.guestOnly, hero: () => "guest", head: HEADLINES.guest },
  { key: "away-empty", when: (s) => viewerState(s) === "away" && !anyHome(s), hero: () => "rest", head: HEADLINES["away-empty"] },
  { key: "away-occupied", when: (s) => viewerState(s) === "away", hero: () => "live", head: HEADLINES["away-occupied"] },
  { key: "arriving", when: (s) => viewerState(s) === "arriving", hero: (s) => (anyHome(s) ? "live" : "rest"), head: HEADLINES.arriving },
  { key: "leaving", when: (s) => viewerState(s) === "left", hero: () => "live", head: HEADLINES.leaving },
  { key: "night-waiting", when: (s) => s.time === "night" && othersOut(s).length > 0, hero: () => "night", head: (s) => general(s, null) },
  { key: "waiting", when: (s) => othersOut(s).length > 0, hero: () => "live", head: (s) => general(s, null) },
  { key: (s) => `home-${s.time}`, when: () => true, hero: (s) => (s.time === "night" ? "night" : "live"), head: (s) => general(s, LEAD[s.time]) },
];

export function situation(input) {
  const r = RULES.find((x) => x.when(input));
  return { key: typeof r.key === "function" ? r.key(input) : r.key, headline: r.head(input), heroMode: r.hero(input) };
}

export const DEFAULT_CONFIG = {
  users: { arun: "a1d4401b8b714ebb83f07c5316ab399c", anjali: "6edcc5a09c3144d684077ee362e7394a" },
  people: {
    arun: { person: "person.arun_karunagath", eta: "sensor.arun_eta_home", arriving: "binary_sensor.arun_arriving", justLeft: "binary_sensor.arun_just_left" },
    anjali: { person: "person.anjalipc", eta: "sensor.anjali_eta_home", arriving: "binary_sensor.anjali_arriving", justLeft: "binary_sensor.anjali_just_left" },
  },
  sun: "sun.sun",
  attention: "sensor.attention",
  openings: "binary_sensor.house_exits_open_status",
  lights: {},
  media: [],
  laundry: { Washer: "sensor.washer_status", Dryer: "sensor.dryer_status" },
  guestEntity: null,
};

export function inputFromHass(hass, userId, config = {}) {
  const c = { ...DEFAULT_CONFIG, ...config };
  const st = hass.states;
  const live = (id) => {
    const s = id && st[id];
    return s && s.state !== "unavailable" && s.state !== "unknown" ? s : null;
  };
  const now = c.now || new Date();
  const sun = live(c.sun);
  let sunset = sun && sun.attributes.next_setting ? new Date(sun.attributes.next_setting) : null;
  if (sunset && sun.state === "below_horizon" && now.getHours() >= 12) sunset = new Date(sunset.getTime() - 24 * HOUR);
  const people = {};
  for (const [k, e] of Object.entries(c.people)) {
    const eta = live(e.eta);
    const p = st[e.person];
    people[k] = {
      state: p ? p.state : "unknown",
      arriving: !!live(e.arriving) && st[e.arriving].state === "on",
      justLeft: !!live(e.justLeft) && st[e.justLeft].state === "on",
      eta: eta && isFinite(Number(eta.state)) ? Number(eta.state) : null,
    };
  }
  const viewer = Object.keys(c.users).find((k) => c.users[k] === userId) || "guest";
  const att = live(c.attention);
  const open = live(c.openings);
  const lights = Object.entries(c.lights);
  const player = c.media.map((e) => st[e]).find((s) => s && s.state === "playing");
  const laundry = Object.entries(c.laundry).map(([n, e]) => [n, live(e)]).filter(([, s]) => s);
  return {
    now,
    time: timeOfDay(now, sun ? sun.attributes.elevation : undefined, sunset),
    viewer,
    people,
    guestOnly: !!live(c.guestEntity) && st[c.guestEntity].state === "on",
    lightsOn: lights.length ? lights.filter(([, e]) => st[e] && st[e].state === "on").map(([n]) => n) : null,
    openings: open ? (open.attributes.open_names || "").split(", ").filter(Boolean) : null,
    attention: att && Array.isArray(att.attributes.items) ? att.attributes.items.filter((i) => i.id !== "open").map((i) => i.label) : null,
    media: player ? { name: player.attributes.friendly_name || player.entity_id, title: player.attributes.media_title || null } : null,
    laundry: laundry.length
      ? { running: laundry.filter(([, s]) => s.state === "Running").map(([n]) => n), done: laundry.filter(([, s]) => s.state === "Done").map(([n]) => n) }
      : null,
  };
}
