// Living-room music player: a mini-media-player re-pointed per mode (Music Assistant, HEOS) plus receiver volume, input and sound mode.

const STYLE = `
:host { display: block; min-width: 0; --mini-media-player-artwork-opacity: 0.35; }
#mini { min-width: 0; max-width: 100%; overflow: hidden; border-radius: 12px; }
ha-card { min-width: 0; overflow: hidden; padding: 6px 10px 10px; display: flex; flex-direction: column; gap: 6px; }
.bar { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; min-width: 0; }
.modes { display: flex; gap: 2px; padding: 2px; border-radius: 18px; background: color-mix(in srgb, var(--secondary-text-color) 10%, transparent); }
.btn { display: inline-flex; align-items: center; justify-content: center; width: 36px; height: 36px; padding: 0; border: 0; border-radius: 50%; cursor: pointer; flex: none;
  color: var(--secondary-text-color); background: none; }
.btn:hover { background: color-mix(in srgb, var(--secondary-text-color) 14%, transparent); }
.btn.on { color: var(--primary-color); background: color-mix(in srgb, var(--primary-color) 16%, transparent); }
.modes .btn { width: 32px; height: 32px; }
.modes .btn.on { color: var(--text-primary-color, #fff); background: var(--primary-color); }
.btn[disabled] { opacity: 0.4; cursor: default; }
ha-icon { --mdc-icon-size: 20px; }
.vol { flex: 1 1 120px; min-width: 120px; display: flex; align-items: center; gap: 6px; color: var(--secondary-text-color); }
.vol input { flex: 1; min-width: 0; height: 24px; margin: 0; -webkit-appearance: none; appearance: none; background: transparent; cursor: pointer; }
.vol input::-webkit-slider-runnable-track { height: 4px; border-radius: 2px; background: linear-gradient(to right, var(--primary-color) var(--p, 0%), color-mix(in srgb, var(--secondary-text-color) 30%, transparent) var(--p, 0%)); }
.vol input::-moz-range-track { height: 4px; border-radius: 2px; background: color-mix(in srgb, var(--secondary-text-color) 30%, transparent); }
.vol input::-moz-range-progress { height: 4px; border-radius: 2px; background: var(--primary-color); }
.vol input::-webkit-slider-thumb { -webkit-appearance: none; width: 16px; height: 16px; margin-top: -6px; border-radius: 50%; border: 0; background: var(--primary-color); }
.vol input::-moz-range-thumb { width: 16px; height: 16px; border-radius: 50%; border: 0; background: var(--primary-color); }
.vol input:disabled { opacity: 0.35; cursor: default; }
.vol.off { opacity: 0.6; }
.two { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 8px; }
.pick { position: relative; display: flex; align-items: center; gap: 10px; min-height: 44px; padding: 0 12px; border-radius: 12px; cursor: pointer;
  color: var(--primary-text-color); background: color-mix(in srgb, var(--secondary-text-color) 10%, transparent); }
.pick:hover { background: color-mix(in srgb, var(--secondary-text-color) 16%, transparent); }
.pick .cap { flex: 1; min-width: 0; display: flex; flex-direction: column; font-size: 14px; font-weight: 500; line-height: 1.2; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.pick small { font-size: 11px; font-weight: 400; color: var(--secondary-text-color); }
.pick select { position: absolute; inset: 0; width: 100%; height: 100%; opacity: 0; cursor: pointer; }
.hint { font-size: 12px; color: var(--secondary-text-color); padding: 2px 6px; }
option { background: var(--card-background-color, #1c1c1c); color: var(--primary-text-color, #eee); }
`;

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const isOn = (st) => st && !["off", "unavailable", "unknown"].includes(st.state);
const ic = (n) => `<ha-icon icon="mdi:${n}"></ha-icon>`;
const opts = (list, cur) => list.map((x) => `<option value="${esc(x)}"${x === cur ? " selected" : ""}>${esc(x)}</option>`).join("");

class HomeTheaterCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.ma || !config.heos || !config.receiver) {
      throw new Error("home-theater-card: ma, heos and receiver are required");
    }
    this._config = config;
    this._sig = "";
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      this.shadowRoot.addEventListener("click", (e) => this._click(e));
      this.shadowRoot.addEventListener("change", (e) => this._change(e));
      this.shadowRoot.addEventListener("input", (e) => { if (e.target.dataset.a === "volume") e.target.style.setProperty("--p", `${e.target.value}%`); });
    }
  }

  getCardSize() { return 3; }

  getGridOptions() { return { columns: 12, min_columns: 6 }; }

  set hass(hass) {
    this._hass = hass;
    if (!this._config) return;
    this._render();
    if (this._mini) this._mini.hass = hass;
    this._syncVolume();
  }

  _syncVolume() {
    const inp = this.shadowRoot && this.shadowRoot.querySelector(".vol input");
    const rcv = this._st(this._config.receiver);
    if (!inp || !rcv || this.shadowRoot.activeElement === inp) return;
    const v = Math.round((rcv.attributes.volume_level ?? 0) * 100);
    inp.value = v;
    inp.style.setProperty("--p", `${v}%`);
  }

  _st(id) { return id ? this._hass.states[id] : undefined; }

  _mode() {
    const c = this._config;
    if (this._pick) return this._pick;
    const heos = this._st(c.heos);
    const ma = this._st(c.ma);
    if (heos && ["playing", "paused", "buffering"].includes(heos.state) && !(ma && ma.state === "playing")) return "heos";
    return "ma";
  }

  _miniConfig(mode) {
    const c = this._config;
    const base = { type: "custom:mini-media-player", name: c.name || "Living room", artwork: "cover", icon: c.icon || "mdi:home-theater", info: "scroll", group: true, hide: { volume: true, mute: true, power: true } };
    if (mode === "heos") {
      const skip = new Set(c.heos_exclude || []);
      const list = ((this._st(c.heos) || { attributes: {} }).attributes.source_list || []).filter((x) => x && !skip.has(x));
      return {
        ...base,
        entity: c.heos,
        hide: { ...base.hide, play_pause: true, play_stop: false, prev: true, next: true },
        shortcuts: { attribute: "source", label: "Radio", list: list.map((p) => ({ name: p, type: "source", id: p })) },
      };
    }
    return {
      ...base,
      entity: c.ma,
      ...((c.group_with || []).length ? { speaker_group: { platform: "media_player", entities: (c.group_with || []).map((id) => ({ entity_id: id, name: (c.labels || {})[id] })) } } : {}),
    };
  }

  _click(e) {
    const el = e.target.closest("[data-a]");
    if (!el || el.disabled) return;
    const c = this._config;
    const a = el.dataset.a;
    const v = el.dataset.v;
    const svc = (domain, service, data) => this._hass.callService(domain, service, data);
    if (a === "power") svc("media_player", isOn(this._st(c.receiver)) ? "turn_off" : "turn_on", { entity_id: c.receiver });
    else if (a === "browse") this.dispatchEvent(new CustomEvent("hass-more-info", { detail: { entityId: this._mode() === "heos" ? c.heos : c.ma }, bubbles: true, composed: true }));
    else if (a === "tune") { this._tune = !this._tune; this._sig = ""; this._render(); }
    else if (a === "mode") {
      const ma = this._st(c.ma);
      if (v === "heos" && ma && (ma.attributes.group_members || []).length > 1) svc("media_player", "unjoin", { entity_id: c.ma });
      this._pick = v;
      this._sig = "";
      this._render();
    }
  }

  _change(e) {
    const el = e.target;
    const c = this._config;
    const svc = (service, data) => this._hass.callService("media_player", service, data);
    if (el.dataset.a === "input") svc("select_source", { entity_id: c.receiver, source: el.value });
    else if (el.dataset.a === "sound") svc("select_sound_mode", { entity_id: c.receiver, sound_mode: el.value });
    else if (el.dataset.a === "volume") svc("volume_set", { entity_id: c.receiver, volume_level: Number(el.value) / 100 });
  }

  _render() {
    const c = this._config;
    const rcv = this._st(c.receiver);
    const mode = this._mode();
    const on = isOn(rcv);
    const ra = (rcv && rcv.attributes) || {};
    const heos = this._st(c.heos);
    const tune = !!this._tune;
    const miniCfg = this._miniConfig(mode);

    const sig = JSON.stringify([mode, rcv && rcv.state, ra.source, ra.sound_mode, ra.source_list, tune, miniCfg, heos && heos.attributes.source_list]);
    if (sig === this._sig) return;
    this._sig = sig;

    const pick = (a, icon, label, cur, list) => `<label class="pick" title="${label}">${ic(icon)}<span class="cap"><small>${label}</small>${esc(cur || "—")}</span>${ic("chevron-down")}<select data-a="${a}">${opts(list, cur)}</select></label>`;
    const modeBtn = (m, icon, label) => `<button class="btn ${mode === m ? "on" : ""}" title="${label}" data-a="mode" data-v="${m}">${ic(icon)}</button>`;
    const v = Math.round((ra.volume_level ?? 0) * 100);
    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card>
      <div id="mini"></div>
      <div class="bar">
        <div class="modes">
          ${modeBtn("ma", "music", "Music")}${modeBtn("heos", "radio", "HEOS")}
        </div>
        <div class="vol ${on ? "" : "off"}" title="${on ? `Receiver volume ${v}` : "Receiver off"}">${ic(on && v === 0 ? "volume-off" : "volume-medium")}<input type="range" min="0" max="100" value="${v}" style="--p:${v}%" data-a="volume" ${on ? "" : "disabled"}></div>
        <button class="btn" title="Browse media" data-a="browse">${ic("folder-music")}</button>
        <button class="btn ${tune ? "on" : ""}" title="Input and sound mode" data-a="tune">${ic("tune-variant")}</button>
        <button class="btn ${on ? "on" : ""}" title="Receiver power" data-a="power">${ic("power")}</button>
      </div>
      ${tune ? (on ? `<div class="two">
        ${pick("input", "import", "Input", ra.source, ra.source_list || [])}
        ${pick("sound", "surround-sound", "Sound mode", ra.sound_mode, ra.sound_mode_list || [])}
      </div>` : `<div class="hint">Turn the receiver on to change input or sound mode.</div>`) : ""}
    </ha-card>`;

    try {
      if (!this._mini) this._mini = document.createElement("mini-media-player");
      this._mini.setConfig(miniCfg);
      this._mini.hass = this._hass;
      this.shadowRoot.getElementById("mini").appendChild(this._mini);
    } catch (err) {
      this.shadowRoot.getElementById("mini").textContent = `home-theater-card: ${err.message}`;
    }
  }
}

if (typeof customElements !== "undefined" && !customElements.get("home-theater-card")) {
  customElements.define("home-theater-card", HomeTheaterCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "home-theater-card", name: "Home theater card", description: "mini-media-player for TV, Music Assistant and HEOS with receiver volume, input and sound mode." });
}
