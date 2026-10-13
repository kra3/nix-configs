// One card for the receiver: Denon controls, Music Assistant playback + groups, HEOS direct streaming.

const STYLE = `
:host { display: block; }
ha-card { padding: 12px; display: flex; flex-direction: column; gap: 12px; }
.head { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.title { font-weight: 500; font-size: 1.05em; flex: 1 1 auto; min-width: 0; }
.modes { display: flex; gap: 8px; flex-wrap: wrap; }
.row { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }
.hint { color: var(--secondary-text-color); font-size: 0.85em; }
button, select { font: inherit; color: var(--primary-text-color); background: var(--secondary-background-color, transparent);
  border: 1px solid var(--divider-color); border-radius: 18px; min-height: 44px; padding: 0 14px; cursor: pointer; }
button.on { background: var(--primary-color); border-color: var(--primary-color); color: var(--text-primary-color, #fff); }
button.icon { width: 44px; padding: 0; --mdc-icon-size: 22px; display: inline-flex; align-items: center; justify-content: center; }
button[disabled] { opacity: 0.45; cursor: default; }
select { flex: 1 1 140px; min-width: 0; border-radius: 12px; }
.now { display: flex; gap: 12px; align-items: center; }
.art { width: 64px; height: 64px; border-radius: 8px; background: var(--secondary-background-color) center / cover; flex: none; }
.meta { min-width: 0; flex: 1; }
.meta .t { font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.meta .s { color: var(--secondary-text-color); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
input[type=range] { flex: 1 1 160px; min-height: 44px; accent-color: var(--primary-color); }
.sec { display: flex; flex-direction: column; gap: 6px; }
.lbl { color: var(--secondary-text-color); font-size: 0.8em; text-transform: uppercase; letter-spacing: 0.04em; }
`;

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const isOn = (st) => st && !["off", "unavailable", "unknown"].includes(st.state);

class HomeTheaterCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.ma || !config.heos || !config.receiver) {
      throw new Error("home-theater-card: ma, heos and receiver are required");
    }
    this._config = config;
    this._mode = null;
    this._sig = "";
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      this.shadowRoot.addEventListener("click", (e) => this._click(e));
      this.shadowRoot.addEventListener("change", (e) => this._change(e));
    }
  }

  getCardSize() { return 6; }
  getGridOptions() { return { columns: 12, min_columns: 6 }; }

  set hass(hass) {
    this._hass = hass;
    if (this._config) this._render();
  }

  _st(id) { return this._hass.states[id]; }

  _activeMode() {
    const c = this._config;
    if (isOn(c.tv && this._st(c.tv))) return "tv";
    if (this._mode && this._mode !== "tv") return this._mode;
    const heos = this._st(c.heos);
    const ma = this._st(c.ma);
    if (heos && ["playing", "paused", "buffering"].includes(heos.state) && !(ma && ma.state === "playing")) return "heos";
    return "ma";
  }

  _members() {
    const ma = this._st(this._config.ma);
    return (ma && ma.attributes.group_members) || [];
  }

  _call(domain, service, data) {
    this._hass.callService(domain, service, data);
  }

  _click(e) {
    const el = e.target.closest("[data-a]");
    if (!el || el.disabled) return;
    const c = this._config;
    const a = el.dataset.a;
    const v = el.dataset.v;
    const mode = this._activeMode();
    const playerId = mode === "tv" ? c.tv : mode === "heos" ? c.heos : c.ma;
    if (a === "power") {
      const on = isOn(this._st(c.receiver));
      this._call("media_player", on ? "turn_off" : "turn_on", { entity_id: c.receiver });
    } else if (a === "tvpower") {
      this._call("media_player", isOn(this._st(c.tv)) ? "turn_off" : "turn_on", { entity_id: c.tv });
    } else if (a === "tvsource") {
      this._call("media_player", "select_source", { entity_id: c.tv, source: v });
    } else if (a === "mode") {
      if (v === "heos" && this._members().length > 1) this._call("media_player", "unjoin", { entity_id: c.ma });
      this._mode = v;
      this._sig = "";
      this._render();
    } else if (a === "transport") {
      this._call("media_player", v, { entity_id: playerId });
    } else if (a === "preset") {
      this._call("media_player", "select_source", { entity_id: c.heos, source: v });
    } else if (a === "group") {
      const members = this._members();
      if (members.includes(v)) this._call("media_player", "unjoin", { entity_id: v });
      else this._call("media_player", "join", { entity_id: c.ma, group_members: [v] });
    } else if (a === "favourite") {
      this._call("button", "press", { entity_id: c.favourite });
    }
  }

  _change(e) {
    const el = e.target;
    const c = this._config;
    if (el.dataset.a === "input") {
      this._call("media_player", "select_source", { entity_id: c.receiver, source: el.value });
    } else if (el.dataset.a === "sound") {
      this._call("media_player", "select_sound_mode", { entity_id: c.receiver, sound_mode: el.value });
    } else if (el.dataset.a === "volume") {
      this._call("media_player", "volume_set", { entity_id: c.receiver, volume_level: Number(el.value) / 100 });
    }
  }

  _render() {
    const c = this._config;
    const rcv = this._st(c.receiver);
    const mode = this._activeMode();
    const player = this._st(mode === "tv" ? c.tv : mode === "heos" ? c.heos : c.ma);
    const tv = c.tv ? this._st(c.tv) : null;
    const tvOn = isOn(tv);
    const on = isOn(rcv);
    const a = (player && player.attributes) || {};
    const playing = player && player.state === "playing";

    const sig = JSON.stringify([
      mode, rcv && rcv.state, rcv && rcv.attributes, player && player.state,
      a.media_title, a.media_artist, a.entity_picture, a.source_list, a.source, this._members(), tvOn,
      (c.group_with || []).map((id) => { const s = this._st(id); return s && [s.state, s.attributes.friendly_name]; }),
    ]);
    if (sig === this._sig) return;
    this._sig = sig;

    const rcvAttr = (rcv && rcv.attributes) || {};
    const inputs = rcvAttr.source_list || [];
    const sounds = rcvAttr.sound_mode_list || [];
    const vol = Math.round(((rcvAttr.volume_level ?? 0) * 100));
    const opts = (list, cur) => list.map((x) => `<option value="${esc(x)}"${x === cur ? " selected" : ""}>${esc(x)}</option>`).join("");

    let modeBody = "";
    if (mode === "tv") {
      const cur = tv.attributes.source;
      modeBody = `<div class="sec"><div class="lbl">Apps</div><div class="row">${
        (c.tv_shortcuts || []).map((p) => `<button data-a="tvsource" data-v="${esc(p.id)}" class="${p.id === cur ? "on" : ""}">${esc(p.name)}</button>`).join("")
      }</div><div class="hint">TV is on and drives the receiver. Turn the TV off to play music.</div></div>`;
    } else if (mode === "heos") {
      const presets = (this._st(c.heos) && this._st(c.heos).attributes.source_list) || [];
      const cur = this._st(c.heos) && this._st(c.heos).attributes.source;
      modeBody = `<div class="sec"><div class="lbl">Radio &amp; inputs</div><div class="row">${
        presets.map((p) => `<button data-a="preset" data-v="${esc(p)}" class="${p === cur ? "on" : ""}">${esc(p)}</button>`).join("")
      }</div><div class="hint">Streams directly over HEOS. Grouping is Music Assistant only.</div></div>`;
    } else {
      const members = this._members();
      const others = (c.group_with || []).filter((id) => this._st(id));
      const leader = members.length > 1 && members[0] !== c.ma ? members[0] : null;
      modeBody = `<div class="sec"><div class="lbl">Play together with</div><div class="row">${
        others.map((id) => {
          const s = this._st(id);
          const joined = members.includes(id);
          const name = s.attributes.friendly_name || id;
          const busy = !joined && ["playing", "paused"].includes(s.state);
          return `<button data-a="group" data-v="${esc(id)}" class="${joined ? "on" : ""}">${esc(name)}${busy ? " (playing)" : ""}</button>`;
        }).join("")
      }</div><div class="hint">${
        leader ? "Following another group." : members.length > 1 ? "Tap a speaker to add or remove it. Others keep playing their own music." : "Tap a speaker to play the same music there."
      }</div></div>`;
    }

    const fav = c.favourite && mode === "ma" ? `<button class="icon" data-a="favourite" title="Favourite this song"><ha-icon icon="mdi:heart"></ha-icon></button>` : "";

    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card>
      <div class="head">
        <div class="title">${esc(c.name || "Home theater")}</div>
        <button class="icon ${on ? "on" : ""}" data-a="power" title="Power"><ha-icon icon="mdi:power"></ha-icon></button>
      </div>
      <div class="modes">
        ${c.tv ? `<button data-a="tvpower" class="${tvOn ? "on" : ""}">TV</button>` : ""}
        <button data-a="mode" data-v="ma" class="${mode === "ma" ? "on" : ""}" ${tvOn ? "disabled" : ""}>Music Assistant</button>
        <button data-a="mode" data-v="heos" class="${mode === "heos" ? "on" : ""}" ${tvOn ? "disabled" : ""}>HEOS</button>
      </div>
      <div class="now">
        <div class="art" style="${a.entity_picture ? `background-image:url('${esc(a.entity_picture)}')` : ""}"></div>
        <div class="meta"><div class="t">${esc(a.media_title || (on ? "Nothing playing" : "Off"))}</div><div class="s">${esc(a.media_artist || a.source || "")}</div></div>
        ${fav}
      </div>
      <div class="row">
        <button class="icon" data-a="transport" data-v="media_previous_track" ${on ? "" : "disabled"}><ha-icon icon="mdi:skip-previous"></ha-icon></button>
        <button class="icon" data-a="transport" data-v="media_play_pause" ${on ? "" : "disabled"}>${playing ? '<ha-icon icon="mdi:pause"></ha-icon>' : '<ha-icon icon="mdi:play"></ha-icon>'}</button>
        <button class="icon" data-a="transport" data-v="media_next_track" ${on ? "" : "disabled"}><ha-icon icon="mdi:skip-next"></ha-icon></button>
        <input type="range" min="0" max="100" value="${vol}" data-a="volume" ${on ? "" : "disabled"}>
      </div>
      ${modeBody}
      <div class="sec"><div class="lbl">Receiver</div><div class="row">
        <select data-a="input" ${on ? "" : "disabled"}>${opts(inputs, rcvAttr.source)}</select>
        <select data-a="sound" ${on ? "" : "disabled"}>${opts(sounds, rcvAttr.sound_mode)}</select>
      </div></div>
    </ha-card>`;
  }
}

if (typeof customElements !== "undefined" && !customElements.get("home-theater-card")) {
  customElements.define("home-theater-card", HomeTheaterCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "home-theater-card", name: "Home theater card", description: "Receiver, Music Assistant groups and HEOS streaming in one card." });
}
