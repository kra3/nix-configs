// TV: a mini-media-player on the TV, big tiles for the pinned apps, and popups for the other apps and the inputs.

const STYLE = `
:host { display: block; height: 100%; min-width: 0; --mini-media-player-artwork-opacity: 0.35; }
#mini { flex: none; min-width: 0; max-width: 100%; overflow: hidden; border-radius: 12px; }
ha-card { position: relative; min-width: 0; overflow: hidden; height: 100%; box-sizing: border-box; padding: 6px 10px 10px; display: flex; flex-direction: column; gap: 8px; }
.apps { flex: 1; min-height: 0; overflow-y: auto; display: grid; grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); grid-auto-rows: minmax(52px, 1fr); gap: 8px; }
.app { display: flex; align-items: center; gap: 10px; padding: 0 12px; border: 0; border-radius: 12px; cursor: pointer; font: inherit; font-size: 14px; font-weight: 500; text-align: left;
  color: var(--primary-text-color); background: color-mix(in srgb, var(--secondary-text-color) 10%, transparent); }
.app:hover { background: color-mix(in srgb, var(--secondary-text-color) 16%, transparent); }
.app.on { color: var(--text-primary-color, #fff); background: var(--primary-color); }
.app[disabled] { opacity: 0.4; cursor: default; }
.app span { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.foot { flex: none; display: flex; align-items: center; gap: 8px; min-height: 40px; }
.btn { display: inline-flex; align-items: center; justify-content: center; gap: 6px; height: 40px; padding: 0 14px; border: 0; border-radius: 20px; cursor: pointer; font: inherit; font-size: 13px;
  color: var(--secondary-text-color); background: color-mix(in srgb, var(--secondary-text-color) 10%, transparent); }
.btn:hover { background: color-mix(in srgb, var(--secondary-text-color) 18%, transparent); }
.btn.on { color: var(--primary-color); background: color-mix(in srgb, var(--primary-color) 16%, transparent); }
.btn[disabled] { opacity: 0.4; cursor: default; }
.hint { flex: 1; font-size: 12px; color: var(--secondary-text-color); text-align: right; }
.menu { position: absolute; left: 10px; right: 10px; bottom: 56px; z-index: 2; max-height: 60%; overflow-y: auto; padding: 6px; border-radius: 12px; display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 4px;
  background: var(--card-background-color, #1c1c1c); border: 1px solid var(--divider-color); box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4); }
.menu .app { min-height: 44px; background: none; }
.menu .app:hover { background: color-mix(in srgb, var(--secondary-text-color) 14%, transparent); }
.menu .app.on { background: var(--primary-color); }
ha-icon { --mdc-icon-size: 22px; flex: none; }
`;

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const isOn = (st) => st && !["off", "unavailable", "unknown"].includes(st.state);

class TvCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.entity) throw new Error("tv-card: entity is required");
    this._config = config;
    this._sig = "";
    this._open = "";
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      this.shadowRoot.addEventListener("click", (e) => {
        const t = e.target.closest("[data-id],[data-m]");
        if (t && t.disabled) return;
        if (t && t.dataset.m) this._open = this._open === t.dataset.m ? "" : t.dataset.m;
        else {
          this._open = "";
          if (t) this._hass.callService("media_player", "select_source", { entity_id: this._config.entity, source: t.dataset.id });
        }
        this._sig = "";
        this.hass = this._hass;
      });
    }
  }

  getCardSize() { return 6; }

  getGridOptions() { return { columns: 12, min_columns: 6, rows: 10 }; }

  set hass(hass) {
    this._hass = hass;
    if (!this._config) return;
    const c = this._config;
    const st = hass.states[c.entity];
    const on = isOn(st);
    const cur = st && st.attributes.source;
    const live = (st && st.attributes.source_list) || [];
    const sig = JSON.stringify([on, cur, live, this._open]);
    if (sig !== this._sig) {
      this._sig = sig;
      const present = (a) => !live.length || live.includes(a.id);
      const pinned = (c.apps || []).filter(present);
      const inputs = (c.inputs || []).filter(present);
      const known = new Set([...pinned, ...inputs].map((a) => a.id));
      const hide = new Set(c.hide || []);
      const more = live.filter((n) => n && !known.has(n) && !hide.has(n)).map((n) => ({ name: n, id: n, icon: "mdi:application" }));
      const btn = (a) => `<button class="app ${on && cur === a.id ? "on" : ""}" data-id="${esc(a.id)}" ${on ? "" : "disabled"}><ha-icon icon="${esc(a.icon || "mdi:application")}"></ha-icon><span>${esc(a.name)}</span></button>`;
      const menu = this._open === "apps" ? more : this._open === "inputs" ? inputs : null;
      const curIn = inputs.find((i) => i.id === cur);
      const curApp = more.find((i) => i.id === cur);
      const tool = (m, icon, label, list, active) => list.length ? `<button class="btn ${active || this._open === m ? "on" : ""}" data-m="${m}" title="${label}" ${on ? "" : "disabled"}><ha-icon icon="mdi:${icon}"></ha-icon>${esc(active ? active.name : label)}</button>` : "";
      this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card>
        <div id="mini"></div>
        <div class="apps">${pinned.map(btn).join("")}</div>
        <div class="foot">${tool("apps", "apps", "Apps", more, curApp)}${tool("inputs", "video-input-hdmi", "Inputs", inputs, curIn)}${on ? "" : `<span class="hint">Turn the TV on to launch an app.</span>`}</div>
        ${menu ? `<div class="menu">${menu.map(btn).join("")}</div>` : ""}
      </ha-card>`;
      try {
        if (!this._mini) this._mini = document.createElement("mini-media-player");
        this._mini.setConfig({
          type: "custom:mini-media-player",
          entity: c.entity,
          name: c.name || "TV",
          icon: c.icon || "mdi:television",
          artwork: "cover",
          info: "scroll",
          group: true,
          hide: { volume: true, mute: true },
        });
        this.shadowRoot.getElementById("mini").appendChild(this._mini);
      } catch (err) {
        this.shadowRoot.getElementById("mini").textContent = `tv-card: ${err.message}`;
      }
    }
    if (this._mini) this._mini.hass = hass;
  }
}

if (typeof customElements !== "undefined" && !customElements.get("tv-card")) {
  customElements.define("tv-card", TvCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "tv-card", name: "TV card", description: "mini-media-player for the TV with pinned app tiles and popups for other apps and inputs." });
}
