// Home hero: presence and time of day, weather, sun and moon, alarm chip and attention pills that appear only when active.
import { drill, moreInfo } from "./ds/dom.js?v=12";

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

const COLORS = {
  red: "var(--error-color, #f44336)",
  amber: "#ffb300",
  orange: "var(--warning-color, #ff9800)",
  blue: "var(--info-color, #2196f3)",
};

const WEATHER_ICONS = {
  "clear-night": "mdi:weather-night",
  cloudy: "mdi:weather-cloudy",
  exceptional: "mdi:alert-circle-outline",
  fog: "mdi:weather-fog",
  hail: "mdi:weather-hail",
  lightning: "mdi:weather-lightning",
  "lightning-rainy": "mdi:weather-lightning-rainy",
  partlycloudy: "mdi:weather-partly-cloudy",
  pouring: "mdi:weather-pouring",
  rainy: "mdi:weather-rainy",
  snowy: "mdi:weather-snowy",
  "snowy-rainy": "mdi:weather-snowy-rainy",
  sunny: "mdi:weather-sunny",
  windy: "mdi:weather-windy",
  "windy-variant": "mdi:weather-windy-variant",
};

const ALARM = {
  disarmed: ["mdi:shield-off-outline", "Disarmed", "neutral"],
  armed_away: ["mdi:shield-lock", "Armed away", "good"],
  armed_night: ["mdi:shield-moon", "Armed night", "good"],
  armed_home: ["mdi:shield-home", "Armed home", "good"],
  armed_vacation: ["mdi:shield-airplane", "Armed vacation", "good"],
  armed_custom_bypass: ["mdi:shield-half-full", "Armed", "good"],
  arming: ["mdi:shield-sync", "Arming", "warn"],
  pending: ["mdi:shield-alert", "Pending", "warn"],
  triggered: ["mdi:bell-ring", "Triggered", "bad"],
};

const IDLE = ["none", "unknown", "unavailable", ""];

const titleCase = (s) => String(s).replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());

function whenOk(states, conds, userId) {
  return (conds || []).every((c) => {
    if (c.user !== undefined) return [].concat(c.user).includes(userId);
    const s = states[c.entity];
    const v = s ? s.state : undefined;
    if (c.state !== undefined) return [].concat(c.state).map(String).includes(v);
    if (c.state_not !== undefined) return ![].concat(c.state_not).map(String).includes(v);
    if (c.below !== undefined) return parseFloat(v) < c.below;
    if (c.above !== undefined) return parseFloat(v) > c.above;
    return false;
  });
}

function pillDetail(states, d) {
  if (!d) return "";
  const s = states[d.entity];
  const v = s ? (d.attr ? s.attributes[d.attr] : s.state) : "";
  if (Array.isArray(v)) return v.join(", ");
  return v == null || IDLE.includes(v) ? "" : String(v);
}

const WEATHER_TEXT = { partlycloudy: "Partly cloudy", "clear-night": "Clear night", "lightning-rainy": "Thunder and rain", "snowy-rainy": "Sleet", "windy-variant": "Windy" };

const MOON_ICONS = {
  new_moon: "mdi:moon-new",
  waxing_crescent: "mdi:moon-waxing-crescent",
  first_quarter: "mdi:moon-first-quarter",
  waxing_gibbous: "mdi:moon-waxing-gibbous",
  full_moon: "mdi:moon-full",
  waning_gibbous: "mdi:moon-waning-gibbous",
  last_quarter: "mdi:moon-last-quarter",
  waning_crescent: "mdi:moon-waning-crescent",
};

const clock = (iso) => {
  const d = new Date(iso);
  return isNaN(d) ? "" : d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", hour12: false });
};

function heroModel(states, cfg, userId) {
  const val = (id) => (id && states[id] ? states[id].state : "");
  const presence = val(cfg.presence);
  const period = val(cfg.period);
  const eta = val(cfg.eta);
  const season = val(cfg.season);
  let title;
  let icon;
  let sub;
  if (cfg.name) {
    title = cfg.name;
    icon = "mdi:home";
    sub = [titleCase(presence), titleCase(period)].filter(Boolean).join(" · ");
  } else {
    title = presence === "away" ? "Away" : presence === "home_both" ? "Everyone's home" : "Home";
    icon = presence === "away" ? "mdi:home-export-outline" : "mdi:home-heart";
    sub = titleCase(period) + (IDLE.includes(eta) ? "" : ` · ${eta}`);
  }
  if (!IDLE.includes(season)) sub += ` · ${titleCase(season)}`;
  const w = cfg.weather && states[cfg.weather];
  const weather =
    w && typeof w.attributes.temperature === "number"
      ? {
          temp: Math.round(w.attributes.temperature),
          unit: w.attributes.temperature_unit || "°C",
          icon: WEATHER_ICONS[w.state] || "mdi:weather-cloudy",
          text: IDLE.includes(w.state) ? "" : WEATHER_TEXT[w.state] || titleCase(w.state.replace(/-/g, " ")),
        }
      : null;
  const s = cfg.sun && states[cfg.sun];
  let sun = null;
  if (s) {
    const up = s.state === "above_horizon";
    const at = clock(s.attributes[up ? "next_setting" : "next_rising"]);
    const dusk = up && clock(s.attributes.next_dusk);
    sun = { icon: up ? "mdi:weather-sunset-down" : "mdi:weather-sunset-up", label: `${up ? "Sunset" : "Sunrise"}${at ? ` ${at}` : ""}`, sub: dusk ? `Dusk ${dusk}` : "" };
  }
  const phase = val(cfg.moon);
  const moon = MOON_ICONS[phase] ? { icon: MOON_ICONS[phase], label: titleCase(phase) } : null;
  const a = cfg.alarm && states[cfg.alarm];
  const alarm = a ? { state: a.state, icon: (ALARM[a.state] || ALARM.disarmed)[0], label: (ALARM[a.state] || [0, titleCase(a.state), "neutral"])[1], tone: (ALARM[a.state] || [0, 0, "neutral"])[2] } : null;
  const pills = (cfg.pills || [])
    .map((p, i) => ({ p, i }))
    .filter(({ p }) => whenOk(states, p.when, userId))
    .map(({ p, i }) => ({ i, label: p.label, icon: p.icon, color: COLORS[p.color] || COLORS.blue, detail: pillDetail(states, p.detail) }));
  return { title, icon, sub, weather, sun, moon, alarm, pills };
}

function heroHtml(m) {
  const weather = m.weather
    ? `<button class="weather" data-act="weather" aria-label="Weather ${m.weather.temp}${esc(m.weather.unit)} ${esc(m.weather.text)}"><span class="t"><ha-icon icon="${m.weather.icon}"></ha-icon>${m.weather.temp}${esc(m.weather.unit)}</span>${m.weather.text ? `<span class="c">${esc(m.weather.text)}</span>` : ""}</button>`
    : "";
  const sky = [
    m.sun && `<button class="cell sun" data-act="sky"><ha-icon icon="${m.sun.icon}"></ha-icon><span class="cx"><span class="k">${esc(m.sun.label)}</span>${m.sun.sub ? `<span class="v">${esc(m.sun.sub)}</span>` : ""}</span></button>`,
    m.moon && `<button class="cell moon" data-act="sky"><ha-icon icon="${m.moon.icon}"></ha-icon><span class="cx"><span class="k">${esc(m.moon.label)}</span><span class="v">Moon</span></span></button>`,
  ].filter(Boolean).join("");
  const alarm = m.alarm
    ? `<button class="chip ${m.alarm.tone}" data-act="alarm"><ha-icon icon="${m.alarm.icon}"></ha-icon>${esc(m.alarm.label)}</button>`
    : "";
  const pills = m.pills
    .map(
      (p) =>
        `<button class="chip pill" style="--c:${p.color}" data-act="pill" data-i="${p.i}"><ha-icon icon="${esc(p.icon)}"></ha-icon><span class="lbl">${esc(p.label)}</span>${p.detail ? `<span class="detail">${esc(p.detail)}</span>` : ""}</button>`
    )
    .join("");
  return `<div class="card">
    <div class="top"><span class="badge"><ha-icon icon="${m.icon}"></ha-icon></span><div class="txt"><div class="title">${esc(m.title)}</div><div class="sub">${esc(m.sub)}</div></div>${weather}</div>
    ${sky ? `<div class="sky">${sky}</div>` : ""}
    ${alarm || pills ? `<div class="chips">${alarm}${pills}</div>` : ""}
  </div>`;
}

const STYLE = `
  :host { display: block; }
  ha-card { overflow: hidden; }
  button { font: inherit; color: inherit; border: 0; cursor: pointer; touch-action: manipulation; }
  button:focus-visible { outline: 2px solid var(--primary-color); outline-offset: 2px; }
  .card { padding: 16px; }
  .top { display: flex; align-items: center; gap: 12px; }
  .badge { flex: none; width: 44px; height: 44px; border-radius: 50%; display: grid; place-items: center; color: var(--primary-color); background: color-mix(in srgb, var(--primary-color) 14%, transparent); }
  .badge ha-icon { --mdc-icon-size: 24px; }
  .txt { flex: 1; min-width: 0; }
  .title { font-size: 20px; line-height: 1.2; font-weight: 700; color: var(--primary-text-color); overflow-wrap: anywhere; }
  .sub { font-size: 13px; color: var(--secondary-text-color); margin-top: 2px; }
  .weather { flex: none; min-height: 44px; padding: 4px 8px; border-radius: 12px; background: none; display: flex; flex-direction: column; align-items: flex-end; justify-content: center; }
  .weather .t { display: flex; align-items: center; gap: 6px; font-size: 24px; line-height: 1.1; font-weight: 700; font-variant-numeric: tabular-nums; }
  .weather ha-icon { --mdc-icon-size: 26px; color: var(--secondary-text-color); }
  .weather .c { font-size: 12px; color: var(--secondary-text-color); }
  .sky { display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: 8px; margin-top: 12px; }
  .cell { min-height: 44px; display: flex; align-items: center; gap: 10px; padding: 8px 12px; border-radius: 14px; text-align: left; background: color-mix(in srgb, var(--c) 10%, var(--card-background-color)); --c: var(--secondary-text-color); }
  .cell.sun { --c: var(--warning-color, #ff9800); }
  .cell.moon { --c: var(--primary-color); }
  .cell ha-icon { --mdc-icon-size: 24px; flex: none; color: var(--c); }
  .cx { display: flex; flex-direction: column; min-width: 0; }
  .cx .k { font-size: 13px; font-weight: 600; }
  .cx .v { font-size: 12px; color: var(--secondary-text-color); }
  .chips { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }
  .chip { max-width: 100%; min-height: 32px; display: inline-flex; align-items: center; gap: 6px; padding: 5px 12px 5px 8px; border-radius: 999px; font-size: 13px; font-weight: 600; text-align: left; --c: var(--secondary-text-color); color: var(--c); background: color-mix(in srgb, var(--c) 16%, transparent); }
  .chip ha-icon { --mdc-icon-size: 18px; }
  .chip.good { --c: var(--success-color, #4caf50); }
  .chip.bad { --c: var(--error-color, #f44336); }
  .chip.warn { --c: #ffb300; }
  .lbl { white-space: nowrap; }
  .detail { font-weight: 500; opacity: 0.8; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
`;

class HomeHeroCard extends HTMLElement {
  setConfig(config) {
    this._config = config || {};
    this._html = "";
    if (!this.shadowRoot) this.attachShadow({ mode: "open" });
  }

  getCardSize() {
    return 2;
  }

  getGridOptions() {
    return { columns: 12, min_columns: 6 };
  }

  set hass(hass) {
    this._hass = hass;
    if (this._config) this._render();
  }

  _render() {
    const html = heroHtml(heroModel(this._hass.states, this._config, this._hass.user && this._hass.user.id));
    if (html === this._html) return;
    this._html = html;
    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card>${html}</ha-card>`;
    for (const el of this.shadowRoot.querySelectorAll("[data-act]")) el.addEventListener("click", () => this._tap(el));
  }

  _moreInfo(entityId) {
    moreInfo(this, entityId);
  }

  _tap(el) {
    const cfg = this._config;
    const act = el.dataset.act;
    if (act === "alarm") {
      if (cfg.alarm_detail) {
        if (drill(this, cfg.alarm_detail)) return;
      }
      return this._moreInfo(cfg.alarm);
    }
    if (act === "weather") return (cfg.weather_detail && drill(this, cfg.weather_detail)) || this._moreInfo(cfg.weather);
    if (act === "sky") return (cfg.sun_detail && drill(this, cfg.sun_detail)) || this._moreInfo(cfg.sun);
    const tap = (cfg.pills[Number(el.dataset.i)] || {}).tap || {};
    if (tap.more_info) return this._moreInfo(tap.more_info);
    if (tap.navigate) {
      history.pushState(null, "", tap.navigate);
      window.dispatchEvent(new Event("location-changed"));
      return;
    }
    if (!tap.service) return;
    if (tap.confirm && !window.confirm(tap.confirm)) return;
    const [domain, service] = tap.service.split(".");
    this._hass.callService(domain, service, tap.data || {});
  }
}

if (typeof customElements !== "undefined" && !customElements.get("home-hero-card")) {
  customElements.define("home-hero-card", HomeHeroCard);
  window.customCards = window.customCards || [];
  window.customCards.push({
    type: "home-hero-card",
    name: "Home hero card",
    description: "Presence, weather, sun and moon, alarm chip and attention pills.",
  });
}

if (typeof module !== "undefined") {
  module.exports = { whenOk, heroModel, heroHtml, pillDetail };
}
