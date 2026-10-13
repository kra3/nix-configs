// Room player cards: home-theater-card (TV, Denon, Music Assistant, HEOS) and speaker-card (one MA speaker).

const STYLE = `
:host { display: block; }
ha-card { padding: 12px 14px 14px; display: flex; flex-direction: column; gap: 14px; }
.top { display: flex; align-items: center; gap: 12px; }
.badge { width: 36px; height: 36px; border-radius: 50%; display: flex; align-items: center; justify-content: center; flex: none;
  background: color-mix(in srgb, var(--secondary-text-color) 18%, transparent); color: var(--secondary-text-color); }
.badge.active { background: color-mix(in srgb, var(--primary-color) 22%, transparent); color: var(--primary-color); }
ha-icon { --mdc-icon-size: 20px; }
.txt { flex: 1; min-width: 0; }
.name { font-size: 14px; font-weight: 500; color: var(--primary-text-color); }
.line { font-size: 12px; color: var(--secondary-text-color); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.pill { display: inline-flex; align-items: center; justify-content: center; gap: 8px; min-height: 36px; min-width: 36px; padding: 0 12px; border: 0; border-radius: 999px; cursor: pointer;
  font: inherit; font-size: 13px; font-weight: 600; color: var(--c, var(--secondary-text-color)); background: color-mix(in srgb, var(--c, var(--secondary-text-color)) 16%, transparent); }
.pill.on { --c: var(--primary-color); }
.pill.round { padding: 0; }
.pill[disabled] { opacity: 0.5; cursor: default; }
.pill[hidden] { display: none; }
.lab { font-size: 11px; font-weight: 700; letter-spacing: 0.6px; text-transform: uppercase; color: var(--secondary-text-color); margin: 0 2px 6px; }
.segs { display: grid; grid-template-columns: repeat(auto-fit, minmax(90px, 1fr)); gap: 6px; }
.seg { font: inherit; font-size: 14px; font-weight: 600; min-height: 44px; display: flex; align-items: center; justify-content: center; gap: 8px; border-radius: 12px;
  border: 1px solid var(--divider-color); background: none; color: var(--secondary-text-color); cursor: pointer; }
.seg.on { background: var(--primary-color); border-color: var(--primary-color); color: var(--text-primary-color, #fff); }
.seg[disabled] { opacity: 0.5; cursor: default; }
.chips { display: flex; flex-wrap: wrap; gap: 8px; }
.chip { font: inherit; font-size: 13px; font-weight: 600; min-height: 36px; padding: 0 14px; border-radius: 999px; border: 0; cursor: pointer;
  color: var(--secondary-text-color); background: color-mix(in srgb, var(--secondary-text-color) 16%, transparent); }
.chip.on { color: var(--text-primary-color, #fff); background: var(--primary-color); }
.media { display: flex; align-items: center; gap: 12px; }
.art { width: 56px; height: 56px; border-radius: 12px; background: var(--secondary-background-color) center / cover; flex: none; }
.media .txt .t { font-size: 14px; font-weight: 600; color: var(--primary-text-color); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.ctl { display: flex; align-items: center; gap: 8px; }
.vol { flex: 1; min-width: 60px; display: flex; align-items: center; gap: 10px; }
.vol input { flex: 1; min-width: 0; accent-color: var(--primary-color); }
.val { min-width: 4ch; text-align: right; font-size: 14px; font-weight: 600; font-variant-numeric: tabular-nums; color: var(--primary-text-color); }
.two { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 10px; }
select { width: 100%; box-sizing: border-box; font: inherit; font-size: 14px; font-weight: 600; min-height: 44px; padding: 0 12px; border-radius: 12px;
  border: 1px solid var(--divider-color); background: none; color: var(--primary-text-color); }
select[disabled] { opacity: 0.5; }
.hint { font-size: 13px; line-height: 1.35; color: var(--secondary-text-color); margin: 8px 2px 0; }
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

  getCardSize() { return 4; }

  set hass(hass) {
    this._hass = hass;
    if (this._config) this._render();
  }

  _st(id) { return id ? this._hass.states[id] : undefined; }

  _call(domain, service, data) { this._hass.callService(domain, service, data); }

  _groupChips(leader, candidates) {
    const lead = this._st(leader);
    const members = (lead && lead.attributes.group_members) || [];
    const chips = candidates.filter((id) => this._st(id) && this._st(id).state !== "unavailable").map((id) => {
      const s = this._st(id);
      const joined = members.includes(id);
      return `<button class="chip ${joined ? "on" : ""}" data-a="group" data-v="${esc(id)}">${esc((this._config.labels || {})[id] || s.attributes.friendly_name || id)}${!joined && ["playing", "paused"].includes(s.state) ? " (playing)" : ""}</button>`;
    }).join("");
    return { members, chips };
  }

  _toggleGroup(leader, id) {
    const lead = this._st(leader);
    const members = (lead && lead.attributes.group_members) || [];
    if (members.includes(id)) this._call("media_player", "unjoin", { entity_id: id });
    else this._call("media_player", "join", { entity_id: leader, group_members: [id] });
  }

  _volume(level, enabled) {
    const v = Math.round((level ?? 0) * 100);
    return `<div class="vol">${ic("volume-medium")}<input type="range" min="0" max="100" value="${v}" data-a="volume" ${enabled ? "" : "disabled"}><span class="val">${v}</span></div>`;
  }
}

class HomeTheaterCard extends PlayerBase {
  _validate(c) {
    if (!c || !c.ma || !c.heos || !c.receiver) throw new Error("home-theater-card: ma, heos and receiver are required");
  }

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
      const ma = this._st(c.ma);
      if (v === "heos" && ma && (ma.attributes.group_members || []).length > 1) this._call("media_player", "unjoin", { entity_id: c.ma });
      this._pick = v;
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
    const a = (player && player.attributes) || {};
    const playing = player && player.state === "playing";
    const ra = (rcv && rcv.attributes) || {};
    const heos = this._st(c.heos);
    const { members, chips } = this._groupChips(c.ma, c.group_with || []);

    const sig = JSON.stringify([mode, rcv && rcv.state, ra, player && player.state, a.media_title, a.media_artist, a.entity_picture, a.source, heos && heos.attributes.source_list, members, tvOn,
      (c.group_with || []).map((id) => { const s = this._st(id); return s && [s.state, s.attributes.friendly_name]; })]);
    if (sig === this._sig) return;
    this._sig = sig;

    const title = a.media_title || (mode === "tv" ? a.source : on ? "Nothing playing" : "Off") || "";
    const sub = a.media_artist || (mode === "tv" ? "" : a.source) || "";
    const modeIcon = { tv: "television", ma: "music", heos: "radio" }[mode];
    const line = !on && !tvOn ? "Off" : mode === "tv" ? "TV" : mode === "heos" ? "HEOS" : "Music Assistant";

    let body = "";
    if (mode === "tv") {
      const cur = a.source;
      body = `<div><div class="lab">Apps</div><div class="chips">${(c.tv_shortcuts || []).map((p) => `<button class="chip ${p.id === cur ? "on" : ""}" data-a="tvsource" data-v="${esc(p.id)}">${esc(p.name)}</button>`).join("")}</div>
        <div class="hint">The TV drives the receiver. Turn it off to play music.</div></div>`;
    } else if (mode === "heos") {
      const cur = heos && heos.attributes.source;
      body = `<div><div class="lab">Radio and inputs</div><div class="chips">${((heos && heos.attributes.source_list) || []).map((p) => `<button class="chip ${p === cur ? "on" : ""}" data-a="preset" data-v="${esc(p)}">${esc(p)}</button>`).join("")}</div>
        <div class="hint">Streams directly over HEOS. Grouping is Music Assistant only.</div></div>`;
    } else if (chips) {
      body = `<div><div class="lab">Play together with</div><div class="chips">${chips}</div>
        <div class="hint">${members.length > 1 ? "Tap a speaker to add or remove it. The others keep playing their own music." : "Tap a speaker to play the same music there."}</div></div>`;
    }

    const fav = c.favourite && mode === "ma" ? `<button class="pill round" data-a="favourite" title="Favourite this song">${ic("heart-outline")}</button>` : "";
    const modeBtn = (m, icon, label) => `<button class="seg ${mode === m ? "on" : ""}" data-a="mode" data-v="${m}" ${tvOn ? "disabled" : ""}>${ic(icon)}${label}</button>`;

    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card>
      <div class="top">
        <div class="badge ${on || tvOn ? "active" : ""}">${ic(modeIcon)}</div>
        <div class="txt"><div class="name">${esc(c.name || "Home theater")}</div><div class="line">${line}</div></div>
        <button class="pill round ${on ? "on" : ""}" data-a="power" title="Receiver power">${ic("power")}</button>
      </div>
      <div class="segs">${c.tv ? `<button class="seg ${tvOn ? "on" : ""}" data-a="tvpower">${ic("television")}TV</button>` : ""}${modeBtn("ma", "music", "Music")}${modeBtn("heos", "radio", "HEOS")}</div>
      <div class="media">
        <div class="art" style="${a.entity_picture ? `background-image:url('${esc(a.entity_picture)}')` : ""}"></div>
        <div class="txt"><div class="t">${esc(title)}</div><div class="line">${esc(sub)}</div></div>
        ${fav}
      </div>
      <div class="ctl">
        <button class="pill round" data-a="transport" data-v="media_previous_track" ${on && mode !== "tv" ? "" : "hidden"}>${ic("skip-previous")}</button>
        <button class="pill round on" data-a="transport" data-v="media_play_pause" ${on ? "" : "disabled"}>${ic(playing ? "pause" : "play")}</button>
        <button class="pill round" data-a="transport" data-v="media_next_track" ${on && mode !== "tv" ? "" : "hidden"}>${ic("skip-next")}</button>
        ${this._volume(ra.volume_level, on)}
      </div>
      ${body}
      <div class="two">
        <div><div class="lab">Input</div><select data-a="input" ${on ? "" : "disabled"}>${opts(ra.source_list || [], ra.source)}</select></div>
        <div><div class="lab">Sound mode</div><select data-a="sound" ${on ? "" : "disabled"}>${opts(ra.sound_mode_list || [], ra.sound_mode)}</select></div>
      </div>
    </ha-card>`;
  }
}

class SpeakerCard extends PlayerBase {
  _validate(c) {
    if (!c || !c.entity) throw new Error("speaker-card: entity is required");
  }

  getCardSize() { return 3; }

  getGridOptions() { return { columns: 6, min_columns: 6 }; }

  _click(e) {
    const el = e.target.closest("[data-a]");
    if (!el || el.disabled) return;
    const c = this._config;
    if (el.dataset.a === "play") this._call("media_player", "media_play_pause", { entity_id: c.entity });
    else if (el.dataset.a === "favourite") this._call("button", "press", { entity_id: c.favourite });
    else if (el.dataset.a === "group") {
      const mine = this._st(c.entity);
      const members = (mine && mine.attributes.group_members) || [];
      const id = el.dataset.v;
      if (members.includes(id)) this._call("media_player", "unjoin", { entity_id: id });
      else this._call("media_player", "join", { entity_id: c.entity, group_members: [id] });
    }
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
    const members = a.group_members || [];
    const grouped = members.length > 1;
    const unavailable = s.state === "unavailable";
    const playing = s.state === "playing";
    const { chips } = this._groupChips(c.entity, c.group_with || []);

    const sig = JSON.stringify([s.state, a.media_title, a.media_artist, a.entity_picture, a.volume_level, members,
      (c.group_with || []).map((id) => { const o = this._st(id); return o && [o.state, o.attributes.friendly_name]; })]);
    if (sig === this._sig) return;
    this._sig = sig;

    const line = unavailable ? "Unavailable" : a.media_title ? [a.media_title, a.media_artist].filter(Boolean).join(" · ") : grouped ? "Grouped" : s.state === "idle" ? "Idle" : s.state;
    const fav = c.favourite && playing ? `<button class="pill round" data-a="favourite" title="Favourite this song">${ic("heart-outline")}</button>` : "";

    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card>
      <div class="top">
        <div class="badge ${playing || grouped ? "active" : ""}">${ic(c.icon || "speaker")}</div>
        <div class="txt"><div class="name">${esc(c.name || a.friendly_name)}</div><div class="line">${esc(line)}</div></div>
        ${fav}
        <button class="pill round ${playing ? "on" : ""}" data-a="play" ${unavailable ? "disabled" : ""}>${ic(playing ? "pause" : "play")}</button>
      </div>
      <div class="ctl">${this._volume(a.volume_level, !unavailable)}</div>
      ${chips ? `<div><div class="lab">Play together with</div><div class="chips">${chips}</div></div>` : ""}
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
