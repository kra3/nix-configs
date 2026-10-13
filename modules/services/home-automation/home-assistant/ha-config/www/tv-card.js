// TV: header with the pinned apps and power, transport, and popups for other apps, inputs and the remote.

const STYLE = `
:host { display: block; height: 100%; min-width: 0; }
ha-card { position: relative; min-width: 0; overflow: hidden; height: 100%; box-sizing: border-box; padding: 8px 10px 10px; display: flex; flex-direction: column; justify-content: space-between; gap: 6px; }
.head { display: flex; align-items: center; gap: 10px; min-height: 48px; }
.who { display: flex; align-items: center; gap: 10px; min-width: 0; flex: none; }
.who ha-icon { --mdc-icon-size: 26px; color: var(--primary-color); }
.n { display: flex; flex-direction: column; font-size: 15px; font-weight: 500; line-height: 1.2; min-width: 0; }
.n small { font-size: 11px; font-weight: 400; color: var(--secondary-text-color); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 90px; }
.sp { flex: 1; }
.apps { flex: none; min-width: 0; display: flex; gap: 6px; }
.app { display: flex; align-items: center; gap: 10px; padding: 0 12px; border: 0; border-radius: 12px; cursor: pointer; font: inherit; font-size: 14px; font-weight: 500; text-align: left;
  color: var(--primary-text-color); background: color-mix(in srgb, var(--secondary-text-color) 10%, transparent); }
.app:hover { background: color-mix(in srgb, var(--secondary-text-color) 16%, transparent); }
.app.on { color: var(--text-primary-color, #fff); background: var(--primary-color); }
.app[disabled] { opacity: 0.4; cursor: default; }
.app span { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.apps .app { flex: 1 1 0; min-width: 0; height: 38px; padding: 0; justify-content: center; }
.apps .app span { display: none; }
.app img { width: 24px; height: 24px; border-radius: 5px; object-fit: contain; flex: none; }
.apps .app ha-icon { --mdc-icon-size: 22px; }
.ib { display: inline-flex; align-items: center; justify-content: center; width: 40px; height: 40px; padding: 0; border: 0; border-radius: 50%; cursor: pointer; flex: none;
  color: var(--primary-text-color); background: none; }
.ib:hover { background: color-mix(in srgb, var(--secondary-text-color) 16%, transparent); }
.ib.on { color: var(--primary-color); background: color-mix(in srgb, var(--primary-color) 16%, transparent); }
.ib[disabled] { opacity: 0.4; cursor: default; }
.foot { flex: none; display: flex; align-items: center; gap: 8px; min-height: 40px; }
.btn { display: inline-flex; align-items: center; justify-content: center; gap: 6px; height: 40px; padding: 0 14px; border: 0; border-radius: 20px; cursor: pointer; font: inherit; font-size: 13px;
  color: var(--secondary-text-color); background: color-mix(in srgb, var(--secondary-text-color) 10%, transparent); }
.btn:hover { background: color-mix(in srgb, var(--secondary-text-color) 18%, transparent); }
.btn.on { color: var(--primary-color); background: color-mix(in srgb, var(--primary-color) 16%, transparent); }
.btn[disabled] { opacity: 0.4; cursor: default; }
.hint { flex: 1; font-size: 12px; color: var(--secondary-text-color); text-align: right; }
.menu { position: absolute; left: 10px; right: 10px; bottom: 56px; z-index: 2; max-height: 70%; overflow-y: auto; padding: 6px; border-radius: 12px; display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 4px;
  background: var(--card-background-color, #1c1c1c); border: 1px solid var(--divider-color); box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4); }
.menu .app { min-height: 44px; background: none; }
.menu .app:hover { background: color-mix(in srgb, var(--secondary-text-color) 14%, transparent); }
.menu .app.on { background: var(--primary-color); }
.pad { grid-template-columns: repeat(4, 1fr); left: auto; width: min(100%, 260px); max-height: none; }
.pad button { aspect-ratio: 1; display: flex; align-items: center; justify-content: center; border: 0; border-radius: 12px; cursor: pointer; padding: 0; color: var(--primary-text-color);
  background: color-mix(in srgb, var(--secondary-text-color) 10%, transparent); }
.pad button:hover { background: color-mix(in srgb, var(--secondary-text-color) 20%, transparent); }
.pad button.ok { color: var(--text-primary-color, #fff); background: var(--primary-color); }
ha-icon { --mdc-icon-size: 22px; flex: none; }
`;

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const PAD = [
  ["BACK", "arrow-left", "Back"], ["UP", "chevron-up", "Up"], ["HOME", "home", "Home"], ["EXIT", "close", "Exit"],
  ["LEFT", "chevron-left", "Left"], ["ENTER", "circle", "OK"], ["RIGHT", "chevron-right", "Right"], ["INFO", "information-outline", "Info"],
  ["CHANNELDOWN", "minus", "Channel down"], ["DOWN", "chevron-down", "Down"], ["CHANNELUP", "plus", "Channel up"], ["MUTE", "volume-off", "Mute"],
  ["PLAY", "play", "Play"], ["PAUSE", "pause", "Pause"], ["VOLUMEDOWN", "volume-minus", "Volume down"], ["VOLUMEUP", "volume-plus", "Volume up"],
];
const iconStore = () => { try { return JSON.parse(localStorage.getItem("tv-card-icons") || "{}"); } catch (e) { return {}; } };
const isOn = (st) => st && !["off", "unavailable", "unknown"].includes(st.state);
const ic = (n) => `<ha-icon icon="mdi:${n}"></ha-icon>`;

class TvCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.entity) throw new Error("tv-card: entity is required");
    this._config = config;
    this._sig = "";
    this._open = "";
    this._icons = iconStore();
    this._tried = {};
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      this.shadowRoot.addEventListener("click", (e) => {
        const t = e.target.closest("[data-id],[data-m],[data-b],[data-t]");
        const id = this._config.entity;
        const svc = (service, data) => this._hass.callService("media_player", service, { entity_id: id, ...data });
        if (t && t.disabled) return;
        if (t && t.dataset.b) { this._hass.callService("webostv", "button", { entity_id: id, button: t.dataset.b }); return; }
        if (t && t.dataset.t) {
          const st = this._hass.states[id];
          if (t.dataset.t === "power") svc(isOn(st) ? "turn_off" : "turn_on");
          else if (t.dataset.t === "toggle") svc(st && st.state === "playing" ? "media_pause" : "media_play");
          else svc(t.dataset.t);
          return;
        }
        if (t && t.dataset.m) this._open = this._open === t.dataset.m ? "" : t.dataset.m;
        else {
          this._open = "";
          if (t) svc("select_source", { source: t.dataset.id });
        }
        this._sig = "";
        this.hass = this._hass;
      });
    }
  }

  getCardSize() { return 3; }

  getGridOptions() { return { columns: 12, min_columns: 6, rows: 2 }; }

  set hass(hass) {
    this._hass = hass;
    if (!this._config) return;
    const c = this._config;
    const st = hass.states[c.entity];
    const on = isOn(st);
    const cur = st && st.attributes.source;
    const live = (st && st.attributes.source_list) || [];
    const picture = st && st.attributes.entity_picture;
    if (on && picture && cur && (c.apps || []).some((a) => a.id === cur) && !this._icons[cur] && !this._tried[cur]) {
      this._tried[cur] = true;
      fetch(picture).then((r) => (r.ok ? r.blob() : Promise.reject())).then((b) => new Promise((res) => { const f = new FileReader(); f.onload = () => res(f.result); f.readAsDataURL(b); }))
        .then((d) => { this._icons[cur] = d; try { localStorage.setItem("tv-card-icons", JSON.stringify(this._icons)); } catch (e) { /* storage full */ } this._sig = ""; this.hass = this._hass; })
        .catch(() => {});
    }
    const title = (st && st.attributes.media_title) || "";
    const sig = JSON.stringify([st && st.state, cur, title, live, this._open, Object.keys(this._icons)]);
    if (sig === this._sig) return;
    this._sig = sig;
    const present = (a) => !live.length || live.includes(a.id);
    const pinned = (c.apps || []).filter(present);
    const inputs = (c.inputs || []).filter(present);
    const known = new Set([...pinned, ...inputs].map((a) => a.id));
    const hide = new Set(c.hide || []);
    const more = live.filter((n) => n && !known.has(n) && !hide.has(n)).map((n) => ({ name: n, id: n, icon: "mdi:application" }));
    const btn = (a) => `<button class="app ${on && cur === a.id ? "on" : ""}" data-id="${esc(a.id)}" title="${esc(a.name)}" ${on ? "" : "disabled"}>${this._icons[a.id] ? `<img src="${this._icons[a.id]}" alt="">` : `<ha-icon icon="${esc(a.icon || "mdi:application")}"></ha-icon>`}<span>${esc(a.name)}</span></button>`;
    const menu = this._open === "apps" ? more : this._open === "inputs" ? inputs : null;
    const curIn = inputs.find((i) => i.id === cur);
    const curApp = more.find((i) => i.id === cur);
    const tool = (m, icon, label, list, active) => list.length ? `<button class="btn ${active || this._open === m ? "on" : ""}" data-m="${m}" title="${label}" ${on ? "" : "disabled"}>${ic(icon)}${esc(active ? active.name : label)}</button>` : "";
    const state = !st ? "Unavailable" : on ? (cur || st.state) : st.state === "off" ? "Off" : "Unavailable";
    const playing = st && st.state === "playing";
    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card>
      <div class="head">
        <div class="who">${ic(c.icon ? c.icon.replace("mdi:", "") : "television")}<div class="n">${esc(c.name || "TV")}<small>${esc(state)}</small></div></div>
        <span class="sp"></span>
        ${on ? `<button class="ib" data-t="media_previous_track" title="Previous">${ic("skip-previous")}</button><button class="ib" data-t="toggle" title="${playing ? "Pause" : "Play"}">${ic(playing ? "pause" : "play")}</button><button class="ib" data-t="media_next_track" title="Next">${ic("skip-next")}</button>` : ""}
        <button class="ib ${on ? "on" : ""}" data-t="power" title="Power">${ic("power")}</button>
      </div>
      <div class="apps">${pinned.map(btn).join("")}</div>
      <div class="foot">${tool("apps", "apps", "Apps", more, curApp)}${tool("inputs", "video-input-hdmi", "Inputs", inputs, curIn)}<button class="btn ${this._open === "remote" ? "on" : ""}" data-m="remote" title="Remote" ${on ? "" : "disabled"}>${ic("remote")}Remote</button>${on ? "" : `<span class="hint">Power on to launch an app.</span>`}</div>
      ${this._open === "remote" ? `<div class="menu pad">${PAD.map(([b, i, l]) => `<button class="${b === "ENTER" ? "ok" : ""}" data-b="${b}" title="${l}">${ic(i)}</button>`).join("")}</div>` : ""}
      ${menu ? `<div class="menu">${menu.map(btn).join("")}</div>` : ""}
    </ha-card>`;
  }
}

if (typeof customElements !== "undefined" && !customElements.get("tv-card")) {
  customElements.define("tv-card", TvCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "tv-card", name: "TV card", description: "TV header with pinned app icons and power, transport, and popups for apps, inputs and the remote." });
}
