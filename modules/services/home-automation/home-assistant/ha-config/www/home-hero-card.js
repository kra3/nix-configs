// Home hero: presence and time of day, weather, alarm chip and attention pills that appear only when active.

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

function whenOk(states, conds) {
  return (conds || []).every((c) => {
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

function heroModel(states, cfg) {
  const val = (id) => (id && states[id] ? states[id].state : "");
  const presence = val(cfg.presence);
  const period = val(cfg.period);
  const eta = val(cfg.eta);
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
  const w = cfg.weather && states[cfg.weather];
  const weather =
    w && typeof w.attributes.temperature === "number"
      ? { temp: Math.round(w.attributes.temperature), unit: w.attributes.temperature_unit || "°C", icon: WEATHER_ICONS[w.state] || "mdi:weather-cloudy" }
      : null;
  const a = cfg.alarm && states[cfg.alarm];
  const alarm = a ? { state: a.state, icon: (ALARM[a.state] || ALARM.disarmed)[0], label: (ALARM[a.state] || [0, titleCase(a.state), "neutral"])[1], tone: (ALARM[a.state] || [0, 0, "neutral"])[2] } : null;
  const pills = (cfg.pills || [])
    .map((p, i) => ({ p, i }))
    .filter(({ p }) => whenOk(states, p.when))
    .map(({ p, i }) => ({ i, label: p.label, icon: p.icon, color: COLORS[p.color] || COLORS.blue, detail: pillDetail(states, p.detail) }));
  return { title, icon, sub, weather, alarm, pills };
}

function heroHtml(m) {
  const weather = m.weather
    ? `<div class="weather" data-act="weather"><ha-icon icon="${m.weather.icon}"></ha-icon><span>${m.weather.temp}${esc(m.weather.unit)}</span></div>`
    : "";
  const alarm = m.alarm
    ? `<button class="chip ${m.alarm.tone}" data-act="alarm"><ha-icon icon="${m.alarm.icon}"></ha-icon>${esc(m.alarm.label)}</button>`
    : "";
  const pills = m.pills
    .map(
      (p) =>
        `<button class="chip pill" style="--c:${p.color}" data-act="pill" data-i="${p.i}"><ha-icon icon="${esc(p.icon)}"></ha-icon>${esc(p.label)}${p.detail ? `<span class="detail">${esc(p.detail)}</span>` : ""}</button>`
    )
    .join("");
  return `<div class="card">
    <div class="top"><ha-icon class="lead" icon="${m.icon}"></ha-icon><div class="txt"><div class="title">${esc(m.title)}</div><div class="sub">${esc(m.sub)}</div></div>${weather}</div>
    <div class="chips">${alarm}${pills}</div>
  </div>`;
}

const STYLE = `
  :host { display: block; }
  ha-card { overflow: hidden; }
  .card { padding: 14px 16px; }
  .top { display: flex; align-items: center; gap: 12px; }
  .lead { --mdc-icon-size: 28px; color: var(--primary-color); }
  .txt { flex: 1; min-width: 0; }
  .title { font-size: 20px; font-weight: 700; color: var(--primary-text-color); }
  .sub { font-size: 13px; color: var(--secondary-text-color); margin-top: 2px; }
  .weather { display: flex; align-items: center; gap: 6px; font-size: 22px; font-weight: 700; color: var(--primary-text-color); cursor: pointer; }
  .weather ha-icon { --mdc-icon-size: 26px; color: var(--secondary-text-color); }
  .chips { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }
  .chip { max-width: 100%; font: inherit; border: 0; cursor: pointer; display: inline-flex; align-items: center; gap: 6px; padding: 5px 12px 5px 8px; border-radius: 999px; font-size: 13px; font-weight: 600; --c: var(--secondary-text-color); color: var(--c); background: color-mix(in srgb, var(--c) 16%, transparent); }
  .chip ha-icon { --mdc-icon-size: 18px; }
  .chip.good { --c: var(--success-color, #4caf50); }
  .chip.bad { --c: var(--error-color, #f44336); }
  .chip.warn { --c: #ffb300; }
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
    const html = heroHtml(heroModel(this._hass.states, this._config));
    if (html === this._html) return;
    this._html = html;
    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card>${html}</ha-card>`;
    for (const el of this.shadowRoot.querySelectorAll("[data-act]")) el.addEventListener("click", () => this._tap(el));
  }

  _moreInfo(entityId) {
    this.dispatchEvent(new CustomEvent("hass-more-info", { detail: { entityId }, bubbles: true, composed: true }));
  }

  _tap(el) {
    const cfg = this._config;
    const act = el.dataset.act;
    if (act === "alarm") return this._moreInfo(cfg.alarm);
    if (act === "weather") return this._moreInfo(cfg.weather);
    const tap = (cfg.pills[Number(el.dataset.i)] || {}).tap || {};
    if (tap.more_info) return this._moreInfo(tap.more_info);
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
    description: "Presence, weather, alarm chip and attention pills.",
  });
}

if (typeof module !== "undefined") {
  module.exports = { whenOk, heroModel, heroHtml, pillDetail };
}
