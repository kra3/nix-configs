// Room player cards: home-theater-card (TV, Denon, Music Assistant, HEOS) and speaker-card (one MA speaker).

const STYLE = `
:host { display: block; }
ha-card { padding: 10px 12px; display: flex; flex-direction: column; gap: 8px; }
.top { display: flex; align-items: center; gap: 10px; }
.badge { width: 40px; height: 40px; border-radius: 10px; display: flex; align-items: center; justify-content: center; flex: none; background: center / cover;
  background-color: color-mix(in srgb, var(--secondary-text-color) 18%, transparent); color: var(--secondary-text-color); }
.badge.active { background-color: color-mix(in srgb, var(--primary-color) 22%, transparent); color: var(--primary-color); }
.badge.art ha-icon { display: none; }
ha-icon { --mdc-icon-size: 20px; }
.txt { flex: 1; min-width: 0; }
.name { font-size: 14px; font-weight: 500; color: var(--primary-text-color); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.line { font-size: 12px; color: var(--secondary-text-color); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.btn { display: inline-flex; align-items: center; justify-content: center; gap: 6px; width: 36px; height: 36px; padding: 0; border: 0; border-radius: 50%; cursor: pointer; flex: none;
  font: inherit; color: var(--secondary-text-color); background: none; }
.btn:hover { background: color-mix(in srgb, var(--secondary-text-color) 14%, transparent); }
.btn.on { color: var(--primary-color); background: color-mix(in srgb, var(--primary-color) 16%, transparent); }
.btn[disabled] { opacity: 0.4; cursor: default; }
.btn[hidden] { display: none; }
.modes { display: flex; gap: 2px; padding: 2px; border-radius: 18px; background: color-mix(in srgb, var(--secondary-text-color) 10%, transparent); }
.modes .btn { width: 32px; height: 32px; }
.modes .btn.on { color: var(--text-primary-color, #fff); background: var(--primary-color); }
.ctl { display: flex; align-items: center; gap: 2px; }
.vol { flex: 1; min-width: 80px; display: flex; align-items: center; gap: 6px; margin-left: 6px; color: var(--secondary-text-color); }
.vol input { flex: 1; min-width: 0; height: 24px; accent-color: var(--primary-color); }
.chips { display: flex; align-items: center; gap: 6px; overflow-x: auto; scrollbar-width: none; }
.chips > ha-icon { color: var(--secondary-text-color); flex: none; }
.chip { font: inherit; font-size: 12px; font-weight: 600; min-height: 28px; padding: 0 12px; border-radius: 14px; border: 0; cursor: pointer; flex: none; white-space: nowrap;
  color: var(--secondary-text-color); background: color-mix(in srgb, var(--secondary-text-color) 14%, transparent); }
.chip.on { color: var(--text-primary-color, #fff); background: var(--primary-color); }
.two { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 8px; }
select { width: 100%; box-sizing: border-box; font: inherit; font-size: 13px; font-weight: 500; min-height: 36px; padding: 0 10px; border-radius: 10px;
  border: 1px solid var(--divider-color); background: none; color: var(--primary-text-color); }
select[disabled] { opacity: 0.4; }
`;

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const isOn = (st) => st && !["off", "unavailable", "unknown"].includes(st.state);
const ic = (n) => `<ha-icon icon="mdi:${n}"></ha-icon>`;
const opts = (list, cur) => list.map((x) => `<option value="${esc(x)}"${x === cur ? " selected" : ""}>${esc(x)}</option>`).join("");

class PlayerBase extends HTMLElement {
  setConfig(config) {
    this._validate(config);
    this._config = config;
    this._sig = "";
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      this.shadowRoot.addEventListener("click", (e) => this._click(e));
      this.shadowRoot.addEventListener("change", (e) => this._change(e));
    }
  }

  set hass(hass) {
    this._hass = hass;
    if (this._config) this._render();
  }

  _st(id) { return id ? this._hass.states[id] : undefined; }

  _call(domain, service, data) { this._hass.callService(domain, service, data); }

  _members(leader) {
    const s = this._st(leader);
    return (s && s.attributes.group_members) || [];
  }

  _groupRow(leader, candidates) {
    const members = this._members(leader);
    const labels = this._config.labels || {};
    const chips = candidates.filter((id) => this._st(id) && this._st(id).state !== "unavailable").map((id) => {
      const s = this._st(id);
      return `<button class="chip ${members.includes(id) ? "on" : ""}" data-a="group" data-v="${esc(id)}">${esc(labels[id] || s.attributes.friendly_name || id)}</button>`;
    }).join("");
    return chips ? `<div class="chips" title="Tap a speaker to play the same music there; tap again to leave">${ic("link-variant")}${chips}</div>` : "";
  }

  _toggleGroup(leader, id) {
    if (this._members(leader).includes(id)) this._call("media_player", "unjoin", { entity_id: id });
    else this._call("media_player", "join", { entity_id: leader, group_members: [id] });
  }

  _volume(level, enabled) {
    const v = Math.round((level ?? 0) * 100);
    return `<div class="vol" title="Volume ${v}">${ic(v === 0 ? "volume-off" : "volume-medium")}<input type="range" min="0" max="100" value="${v}" data-a="volume" ${enabled ? "" : "disabled"}></div>`;
  }

  _badge(on, picture, icon) {
    return `<div class="badge ${on ? "active" : ""} ${picture ? "art" : ""}" style="${picture ? `background-image:url('${esc(picture)}')` : ""}">${ic(icon)}</div>`;
  }
}

class HomeTheaterCard extends PlayerBase {
  _validate(c) {
    if (!c || !c.ma || !c.heos || !c.receiver) throw new Error("home-theater-card: ma, heos and receiver are required");
  }

  getCardSize() { return 3; }

  getGridOptions() { return { columns: 12, min_columns: 6 }; }

  _mode() {
    const c = this._config;
    if (isOn(this._st(c.tv))) return "tv";
    if (this._pick && this._pick !== "tv") return this._pick;
    const heos = this._st(c.heos);
    const ma = this._st(c.ma);
    if (heos && ["playing", "paused", "buffering"].includes(heos.state) && !(ma && ma.state === "playing")) return "heos";
    return "ma";
  }

  _click(e) {
    const el = e.target.closest("[data-a]");
    if (!el || el.disabled) return;
    const c = this._config;
    const a = el.dataset.a;
    const v = el.dataset.v;
    const mode = this._mode();
    const player = mode === "tv" ? c.tv : mode === "heos" ? c.heos : c.ma;
    if (a === "power") {
      this._call("media_player", isOn(this._st(c.receiver)) ? "turn_off" : "turn_on", { entity_id: c.receiver });
    } else if (a === "tvpower") {
      this._call("media_player", isOn(this._st(c.tv)) ? "turn_off" : "turn_on", { entity_id: c.tv });
    } else if (a === "tvsource") {
      this._call("media_player", "select_source", { entity_id: c.tv, source: v });
    } else if (a === "mode") {
      if (v === "heos" && this._members(c.ma).length > 1) this._call("media_player", "unjoin", { entity_id: c.ma });
      this._pick = v;
      this._sig = "";
      this._render();
    } else if (a === "tune") {
      this._tune = !this._tune;
      this._sig = "";
      this._render();
    } else if (a === "transport") {
      this._call("media_player", v, { entity_id: player });
    } else if (a === "preset") {
      this._call("media_player", "select_source", { entity_id: c.heos, source: v });
    } else if (a === "group") {
      this._toggleGroup(c.ma, v);
    } else if (a === "favourite") {
      this._call("button", "press", { entity_id: c.favourite });
    }
  }

  _change(e) {
    const el = e.target;
    const c = this._config;
    const a = el.dataset.a;
    if (a === "input") this._call("media_player", "select_source", { entity_id: c.receiver, source: el.value });
    else if (a === "sound") this._call("media_player", "select_sound_mode", { entity_id: c.receiver, sound_mode: el.value });
    else if (a === "volume") this._call("media_player", "volume_set", { entity_id: c.receiver, volume_level: Number(el.value) / 100 });
  }

  _render() {
    const c = this._config;
    const rcv = this._st(c.receiver);
    const mode = this._mode();
    const player = this._st(mode === "tv" ? c.tv : mode === "heos" ? c.heos : c.ma);
    const tvOn = isOn(this._st(c.tv));
    const on = isOn(rcv);
    const a = (on || tvOn) && player ? player.attributes : {};
    const playing = on && player && player.state === "playing";
    const ra = (rcv && rcv.attributes) || {};
    const heos = this._st(c.heos);
    const members = this._members(c.ma);
    const tune = !!this._tune;

    const sig = JSON.stringify([mode, rcv && rcv.state, ra, player && player.state, a.media_title, a.media_artist, a.entity_picture, a.source, heos && heos.attributes.source_list, members, tvOn, tune,
      (c.group_with || []).map((id) => { const s = this._st(id); return s && [s.state, s.attributes.friendly_name]; })]);
    if (sig === this._sig) return;
    this._sig = sig;

    const title = a.media_title || (mode === "tv" ? a.source : "") || "";
    const line = !on && !tvOn ? "Off" : title ? [title, mode === "tv" ? "" : a.media_artist].filter(Boolean).join(" · ") : mode === "heos" ? "HEOS" : mode === "tv" ? "TV" : "Idle";
    const modeBtn = (m, icon, label) => `<button class="btn ${mode === m ? "on" : ""}" title="${label}" data-a="mode" data-v="${m}" ${tvOn ? "disabled" : ""}>${ic(icon)}</button>`;

    let row = "";
    if (mode === "tv") {
      const cur = a.source;
      row = `<div class="chips">${ic("apps")}${(c.tv_shortcuts || []).map((p) => `<button class="chip ${p.id === cur ? "on" : ""}" data-a="tvsource" data-v="${esc(p.id)}">${esc(p.name)}</button>`).join("")}</div>`;
    } else if (mode === "heos") {
      const cur = heos && heos.attributes.source;
      row = `<div class="chips">${ic("radio")}${((heos && heos.attributes.source_list) || []).map((p) => `<button class="chip ${p === cur ? "on" : ""}" data-a="preset" data-v="${esc(p)}">${esc(p)}</button>`).join("")}</div>`;
    } else {
      row = this._groupRow(c.ma, c.group_with || []);
    }

    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card>
      <div class="top">
        ${this._badge(on || tvOn, on || tvOn ? a.entity_picture : "", { tv: "television", ma: "music", heos: "radio" }[mode])}
        <div class="txt"><div class="name">${esc(c.name || "Home theater")}</div><div class="line">${esc(line)}</div></div>
        <div class="modes">
          ${c.tv ? `<button class="btn ${tvOn ? "on" : ""}" title="TV" data-a="tvpower">${ic("television")}</button>` : ""}
          ${modeBtn("ma", "music", "Music")}${modeBtn("heos", "radio", "HEOS")}
        </div>
        <button class="btn ${tune ? "on" : ""}" title="Input and sound mode" data-a="tune">${ic("tune-variant")}</button>
        <button class="btn ${on ? "on" : ""}" title="Receiver power" data-a="power">${ic("power")}</button>
      </div>
      <div class="ctl">
        <button class="btn" data-a="transport" data-v="media_previous_track" ${on && mode !== "tv" ? "" : "hidden"}>${ic("skip-previous")}</button>
        <button class="btn ${playing ? "on" : ""}" data-a="transport" data-v="media_play_pause" ${on ? "" : "disabled"}>${ic(playing ? "pause" : "play")}</button>
        <button class="btn" data-a="transport" data-v="media_next_track" ${on && mode !== "tv" ? "" : "hidden"}>${ic("skip-next")}</button>
        ${c.favourite && mode === "ma" ? `<button class="btn" title="Favourite this song" data-a="favourite">${ic("heart-outline")}</button>` : ""}
        ${this._volume(ra.volume_level, on)}
      </div>
      ${row}
      ${tune ? `<div class="two">
        <select data-a="input" title="Input" ${on ? "" : "disabled"}>${opts(ra.source_list || [], ra.source)}</select>
        <select data-a="sound" title="Sound mode" ${on ? "" : "disabled"}>${opts(ra.sound_mode_list || [], ra.sound_mode)}</select>
      </div>` : ""}
    </ha-card>`;
  }
}

class SpeakerCard extends PlayerBase {
  _validate(c) {
    if (!c || !c.entity) throw new Error("speaker-card: entity is required");
  }

  getCardSize() { return 2; }

  getGridOptions() { return { columns: 12, min_columns: 6 }; }

  _click(e) {
    const el = e.target.closest("[data-a]");
    if (!el || el.disabled) return;
    const c = this._config;
    if (el.dataset.a === "play") this._call("media_player", "media_play_pause", { entity_id: c.entity });
    else if (el.dataset.a === "favourite") this._call("button", "press", { entity_id: c.favourite });
    else if (el.dataset.a === "group") this._toggleGroup(c.entity, el.dataset.v);
  }

  _change(e) {
    const el = e.target;
    if (el.dataset.a === "volume") this._call("media_player", "volume_set", { entity_id: this._config.entity, volume_level: Number(el.value) / 100 });
  }

  _render() {
    const c = this._config;
    const s = this._st(c.entity);
    if (!s) { this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card><div class="line">${esc(c.entity)} not found</div></ha-card>`; return; }
    const a = s.attributes;
    const members = this._members(c.entity);
    const unavailable = s.state === "unavailable";
    const playing = s.state === "playing";

    const sig = JSON.stringify([s.state, a.media_title, a.media_artist, a.entity_picture, a.volume_level, members,
      (c.group_with || []).map((id) => { const o = this._st(id); return o && [o.state, o.attributes.friendly_name]; })]);
    if (sig === this._sig) return;
    this._sig = sig;

    const line = unavailable ? "Unavailable" : a.media_title ? [a.media_title, a.media_artist].filter(Boolean).join(" · ") : members.length > 1 ? "Grouped" : s.state === "idle" ? "Idle" : s.state;
    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card>
      <div class="top">
        ${this._badge(playing || members.length > 1, a.entity_picture, c.icon || "speaker")}
        <div class="txt"><div class="name">${esc(c.name || a.friendly_name)}</div><div class="line">${esc(line)}</div></div>
        ${c.favourite && playing ? `<button class="btn" title="Favourite this song" data-a="favourite">${ic("heart-outline")}</button>` : ""}
        <button class="btn ${playing ? "on" : ""}" data-a="play" ${unavailable ? "disabled" : ""}>${ic(playing ? "pause" : "play")}</button>
      </div>
      ${this._volume(a.volume_level, !unavailable)}
      ${this._groupRow(c.entity, c.group_with || [])}
    </ha-card>`;
  }
}

if (typeof customElements !== "undefined") {
  if (!customElements.get("home-theater-card")) {
    customElements.define("home-theater-card", HomeTheaterCard);
    window.customCards = window.customCards || [];
    window.customCards.push({ type: "home-theater-card", name: "Home theater card", description: "TV, receiver, Music Assistant groups and HEOS streaming in one card." });
  }
  if (!customElements.get("speaker-card")) {
    customElements.define("speaker-card", SpeakerCard);
    window.customCards = window.customCards || [];
    window.customCards.push({ type: "speaker-card", name: "Speaker card", description: "One Music Assistant speaker with volume and grouping." });
  }
}
