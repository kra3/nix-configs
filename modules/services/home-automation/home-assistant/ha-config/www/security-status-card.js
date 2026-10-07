// Security status: one sentence for the state of the house, what is open and for how long, and arm controls.

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const OPEN_CLASSES = ["door", "window", "garage_door", "opening"];
const GONE = ["unknown", "unavailable"];
const ALARM = {
  disarmed: ["mdi:shield-off-outline", "Disarmed"],
  armed_away: ["mdi:shield-lock", "Armed away"],
  armed_night: ["mdi:shield-moon", "Armed night"],
  armed_home: ["mdi:shield-home", "Armed home"],
  armed_vacation: ["mdi:shield-airplane", "Armed vacation"],
  armed_custom_bypass: ["mdi:shield-half-full", "Armed"],
  arming: ["mdi:shield-sync", "Arming"],
  pending: ["mdi:shield-alert", "Pending"],
  triggered: ["mdi:bell-ring", "Triggered"],
};

const titleCase = (s) => String(s).replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());

function ago(ms, now) {
  const m = Math.max(0, Math.round((now - ms) / 60000));
  if (m < 1) return "just now";
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h} h ${m % 60} min`;
  return `${Math.floor(h / 24)} d`;
}

function areaFor(hass, id, cfg) {
  const over = cfg && cfg.area_override && cfg.area_override[id];
  if (over) return over;
  const e = hass.entities && hass.entities[id];
  const dev = e && e.device_id && hass.devices && hass.devices[e.device_id];
  const areaId = (e && e.area_id) || (dev && dev.area_id);
  return (areaId && hass.areas && hass.areas[areaId] && hass.areas[areaId].name) || "";
}

function secModel(states, areaOf, now, cfg) {
  const skip = new Set(cfg.exclude || []);
  const all = Object.values(states).filter((s) => !skip.has(s.entity_id));
  const name = (s) => (s.attributes.friendly_name || s.entity_id).replace(/\s+Contact(\s+(Door|Window))?$/i, "");
  const where = (s) => areaOf(s.entity_id) || "";
  const openings = all.filter((s) => s.entity_id.startsWith("binary_sensor.") && OPEN_CLASSES.includes(s.attributes.device_class));
  const locks = all.filter((s) => s.entity_id.startsWith("lock."));
  const open = openings
    .filter((s) => s.state === "on")
    .map((s) => ({ id: s.entity_id, name: name(s), area: where(s), since: Date.parse(s.last_changed) }))
    .sort((a, b) => a.since - b.since);
  const unlocked = locks.filter((s) => ["unlocked", "open", "jammed"].includes(s.state)).map((s) => ({ id: s.entity_id, name: name(s), state: s.state }));
  const dead = [...openings, ...locks].filter((s) => GONE.includes(s.state)).map((s) => ({ id: s.entity_id, name: name(s) }));
  const away = (states[cfg.alarm] || {}).state === "armed_away" || (!cfg.alarm && (all.find((s) => s.entity_id.startsWith("alarm_control_panel.")) || {}).state === "armed_away");
  const people = all
    .filter((s) => /^binary_sensor\..*_person_occupancy$/.test(s.entity_id) && !!states["camera." + s.entity_id.slice(14, -17)] !== away && s.state === "on")
    .map((s) => ({ id: s.entity_id, area: where(s) || name(s).replace(/ person.*$/i, "") }));
  const alarm = cfg.alarm ? states[cfg.alarm] : all.find((s) => s.entity_id.startsWith("alarm_control_panel."));
  const astate = alarm ? alarm.state : "unknown";
  const [aicon, alabel] = ALARM[astate] || ["mdi:shield-outline", titleCase(astate)];
  const armed = astate.startsWith("armed_") || astate === "pending";
  const camList = all.filter((s) => s.entity_id.startsWith("camera.") && !GONE.includes(s.state));
  const cams = camList.length;
  const detect = (c) => states["switch." + c.entity_id.slice(7) + "_detect"];
  const camStat = {
    total: cams,
    rec: camList.filter((c) => c.state === "recording").length,
    det: camList.filter((c) => detect(c) && detect(c).state === "on").length,
    off: camList.filter((c) => detect(c) && detect(c).state === "off").map((c) => name(c)),
  };

  let tone;
  let title;
  let sub;
  if (astate === "triggered") {
    tone = "bad";
    title = "Alarm triggered";
    sub = [...open.map((o) => o.name), ...people.map((p) => "Person · " + p.area)].join(", ");
  } else if (armed && (open.length || people.length)) {
    tone = "bad";
    title = people.length ? `Person detected · ${people[0].area}` : `${open[0].name} is open`;
    sub = `${alabel} · ${open.length ? open.length + " open" : "all closed"}`;
  } else if (armed) {
    tone = dead.length ? "warn" : "good";
    title = "Secure";
    sub = `${alabel} · all closed${cams ? ` · ${cams} cameras watching` : ""}`;
  } else if (open.length) {
    tone = dead.length ? "warn" : "neutral";
    title = open.length === 1 ? `${open[0].name} open` : `${open.length} open`;
    sub = `${alabel} · ${open.map((o) => o.name).join(", ")}`;
  } else {
    tone = dead.length || unlocked.length ? "warn" : "neutral";
    title = "All closed";
    sub = `${alabel}${cams ? ` · ${cams} cameras watching` : ""}`;
  }
  const warns = (cfg.warn || []).filter((w) => states[w.entity] && states[w.entity].state === "on").map((w) => ({ id: w.entity, label: w.label, icon: w.icon || "mdi:alert-outline" }));
  const blind = armed && camStat.off.length;
  if ((warns.length || blind) && tone !== "bad") tone = "warn";
  return { tone, title, sub, icon: aicon, alarm: alarm ? alarm.entity_id : "", astate, armed, open, unlocked, dead, people, warns, camStat, blind: blind ? camStat.off : [], now };
}

function secHtml(m, showDead) {
  const chip = (cls, icon, label, extra, attrs) =>
    `<button class="chip ${cls}" ${attrs}><ha-icon icon="${icon}"></ha-icon><span class="lbl">${esc(label)}</span>${extra ? `<span class="detail">${esc(extra)}</span>` : ""}</button>`;
  const chips = [
    ...m.people.map((p) => chip("bad pulse", "mdi:walk", "Person", p.area, `data-act="more" data-id="${esc(p.id)}"`)),
    ...m.open.map((o) => chip(m.armed ? "bad" : "amber", "mdi:door-open", o.name, [o.area, ago(o.since, m.now)].filter(Boolean).join(" · "), `data-act="more" data-id="${esc(o.id)}"`)),
    ...m.unlocked.map((l) => chip("warn", "mdi:lock-open-variant", l.name, l.state, `data-act="more" data-id="${esc(l.id)}"`)),
    ...m.warns.map((w) => chip("warn", w.icon, w.label, "", `data-act="more" data-id="${esc(w.id)}"`)),
    ...(m.blind.length ? [chip("warn", "mdi:cctv-off", "Detection off", m.blind.join(", "), `data-act="none"`)] : []),
    ...(m.camStat.total ? [chip("info", "mdi:cctv", "Cameras", `${m.camStat.rec} recording · ${m.camStat.det} detecting`, `data-act="none"`)] : []),
    ...(m.dead.length ? [chip("warn", "mdi:access-point-off", `${m.dead.length} not reporting`, "", `data-act="dead"`)] : []),
  ].join("");
  const deadRow = showDead && m.dead.length ? `<div class="dead">${m.dead.map((d) => `<button class="link" data-act="more" data-id="${esc(d.id)}">${esc(d.name)}</button>`).join("")}</div>` : "";
  const arm = m.alarm
    ? `<div class="arm"><button class="btn on" data-act="alarm"><ha-icon icon="${m.icon}"></ha-icon>${m.astate === "disarmed" ? "Arm" : "Disarm"}</button></div>`
    : "";
  return `<div class="card ${m.tone}">
    <div class="top"><ha-icon class="lead" icon="${m.icon}"></ha-icon><div class="txt"><div class="title">${esc(m.title)}</div><div class="sub">${esc(m.sub)}</div></div>${arm}</div>
    ${chips ? `<div class="chips">${chips}</div>` : ""}${deadRow}
  </div>`;
}

const STYLE = `
  :host { display: block; }
  ha-card { overflow: hidden; }
  .card { padding: 14px 16px; --c: var(--secondary-text-color); border-left: 4px solid var(--c); }
  .card.good { --c: var(--success-color, #4caf50); }
  .card.warn { --c: #ffb300; }
  .card.bad { --c: var(--error-color, #f44336); }
  .top { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
  .lead { --mdc-icon-size: 30px; color: var(--c); }
  .txt { flex: 1; min-width: 180px; }
  .title { font-size: 20px; font-weight: 700; color: var(--primary-text-color); }
  .sub { font-size: 13px; color: var(--secondary-text-color); margin-top: 2px; }
  .arm { display: flex; gap: 8px; }
  .btn { font: inherit; border: 0; cursor: pointer; display: inline-flex; align-items: center; gap: 6px; padding: 8px 14px; border-radius: 12px; font-size: 13px; font-weight: 600; color: var(--primary-text-color); background: var(--secondary-background-color); }
  .btn ha-icon { --mdc-icon-size: 18px; }
  .btn.on { background: color-mix(in srgb, var(--c) 28%, transparent); color: var(--c); }
  .chips { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }
  .chip { max-width: 100%; font: inherit; border: 0; cursor: pointer; display: inline-flex; align-items: center; gap: 6px; padding: 5px 12px 5px 8px; border-radius: 999px; font-size: 13px; font-weight: 600; --k: var(--secondary-text-color); color: var(--k); background: color-mix(in srgb, var(--k) 16%, transparent); text-align: left; }
  .chip ha-icon { --mdc-icon-size: 18px; }
  .chip.amber { --k: #ffb300; }
  .chip.warn { --k: #ffb300; }
  .chip.bad { --k: var(--error-color, #f44336); }
  .chip.info { cursor: default; }
  .chip.pulse { animation: pulse 1.6s ease-in-out infinite; }
  @keyframes pulse { 50% { opacity: 0.55; } }
  .lbl { white-space: nowrap; }
  .detail { font-weight: 500; opacity: 0.8; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .dead { display: flex; flex-wrap: wrap; gap: 6px 14px; margin-top: 10px; font-size: 12px; }
  .link { font: inherit; border: 0; padding: 0; background: none; cursor: pointer; color: var(--secondary-text-color); text-decoration: underline; }
`;

class SecurityStatusCard extends HTMLElement {
  setConfig(config) {
    this._config = config || {};
    this._html = "";
    this._showDead = false;
    if (!this.shadowRoot) this.attachShadow({ mode: "open" });
  }

  getCardSize() {
    return 2;
  }

  getGridOptions() {
    return { columns: 12, min_columns: 6 };
  }

  connectedCallback() {
    this._timer = setInterval(() => this._hass && this._render(), 30000);
  }

  disconnectedCallback() {
    clearInterval(this._timer);
  }

  set hass(hass) {
    this._hass = hass;
    if (this._popupCard) this._popupCard.hass = hass;
    if (this._config) this._render();
  }

  _render() {
    this._model = secModel(this._hass.states, (id) => areaFor(this._hass, id, this._config), Date.now(), this._config);
    const html = secHtml(this._model, this._showDead);
    if (html === this._html) return;
    this._html = html;
    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card>${html}</ha-card>`;
    for (const el of this.shadowRoot.querySelectorAll("[data-act]")) el.addEventListener("click", () => this._tap(el));
  }

  _moreInfo(entityId) {
    this.dispatchEvent(new CustomEvent("hass-more-info", { detail: { entityId }, bubbles: true, composed: true }));
  }

  _tap(el) {
    const m = this._model;
    const act = el.dataset.act;
    if (act === "more") return this._moreInfo(el.dataset.id);
    if (act === "dead") {
      this._showDead = !this._showDead;
      this._html = "";
      return this._render();
    }
    if (act === "alarm") return this._openAlarmo(m.alarm, m.astate === "disarmed" ? m.open : []);
  }

  async _openAlarmo(entity, open = []) {
    if (this._overlay) return;
    if (!document.getElementById("ssc-style")) {
      const st = document.createElement("style");
      st.id = "ssc-style";
      st.textContent = `
        .ssc-overlay { position: fixed; inset: 0; z-index: 9; background: rgba(0, 0, 0, 0.6); display: flex; align-items: center; justify-content: center; padding: 16px; }
        .ssc-sheet { width: min(420px, 100%); max-height: 92vh; overflow: auto; background: var(--card-background-color, #1c1c1c); border-radius: 16px; padding: 8px 8px 12px; box-sizing: border-box; }
        .ssc-head { display: flex; justify-content: flex-end; }
        .ssc-force { padding: 4px 16px 8px; display: grid; gap: 12px; }
        .ssc-force h3 { margin: 0; font-size: 18px; }
        .ssc-force p { margin: 0; color: var(--secondary-text-color); font-size: 14px; }
        .ssc-force input { font-size: 22px; letter-spacing: 6px; text-align: center; padding: 10px; border-radius: 10px; border: 1px solid var(--divider-color); background: transparent; color: var(--primary-text-color); }
        .ssc-force .row { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
        .ssc-force button { padding: 12px; border-radius: 10px; border: 0; font-size: 15px; cursor: pointer; background: var(--primary-color); color: var(--text-primary-color, #fff); }
        .ssc-force .err { color: var(--error-color, #db4437); min-height: 1em; }
        .ssc-close { background: none; border: 0; color: var(--secondary-text-color); font-size: 26px; line-height: 1; cursor: pointer; padding: 4px 10px; }`;
      document.head.appendChild(st);
    }
    let card;
    if (open.length) {
      card = document.createElement("div");
      card.className = "ssc-force";
      card.innerHTML = `<h3>Arm with sensors open?</h3><p>${open.map((o) => esc(o.name)).join(", ")} will be bypassed.</p><input type="password" inputmode="numeric" autocomplete="off" placeholder="PIN"><div class="err"></div><div class="row"><button data-mode="night">Night</button><button data-mode="away">Away</button></div>`;
      card.addEventListener("click", async (e) => {
        const b = e.target.closest("button[data-mode]");
        if (!b) return;
        try {
          await this._hass.callService("alarmo", "arm", { entity_id: entity, mode: b.dataset.mode, force: true, code: card.querySelector("input").value });
          this._overlay.querySelector(".ssc-close").click();
        } catch (err) {
          card.querySelector(".err").textContent = err.message || "Could not arm";
        }
      });
    } else {
      const helpers = await window.loadCardHelpers();
      card = await helpers.createCardElement({ type: "custom:alarmo-card", entity });
      card.hass = this._hass;
    }
    const ov = document.createElement("div");
    ov.className = "ssc-overlay";
    ov.innerHTML = '<div class="ssc-sheet" role="dialog" aria-modal="true"><div class="ssc-head"><button class="ssc-close" aria-label="Close">×</button></div></div>';
    ov.querySelector(".ssc-sheet").appendChild(card);
    const close = () => {
      document.removeEventListener("keydown", onKey);
      ov.remove();
      this._overlay = null;
      this._popupCard = null;
    };
    const onKey = (e) => {
      if (e.key === "Escape") close();
    };
    ov.addEventListener("click", (e) => {
      if (e.target === ov) close();
    });
    ov.querySelector(".ssc-close").addEventListener("click", close);
    document.addEventListener("keydown", onKey);
    document.body.appendChild(ov);
    this._overlay = ov;
    this._popupCard = open.length ? null : card;
  }
}

if (typeof customElements !== "undefined" && !customElements.get("security-status-card")) {
  customElements.define("security-status-card", SecurityStatusCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "security-status-card", name: "Security status card", description: "House state, open items with durations and arm controls." });
}

if (typeof module !== "undefined") {
  module.exports = { secModel, secHtml, ago };
}
