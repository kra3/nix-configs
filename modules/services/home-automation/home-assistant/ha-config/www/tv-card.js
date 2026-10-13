// TV: a mini-media-player on the TV plus an app launcher grid that fills the column.

const STYLE = `
:host { display: block; height: 100%; min-width: 0; --mini-media-player-artwork-opacity: 0.35; }
#mini { min-width: 0; max-width: 100%; overflow: hidden; border-radius: 12px; }
ha-card { min-width: 0; overflow: hidden; height: 100%; box-sizing: border-box; padding: 6px 10px 10px; display: flex; flex-direction: column; gap: 8px; }
.apps { flex: 1; display: grid; grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); grid-auto-rows: minmax(52px, 1fr); gap: 8px; align-content: stretch; }
.app { display: flex; align-items: center; gap: 10px; padding: 0 12px; border: 0; border-radius: 12px; cursor: pointer; font: inherit; font-size: 14px; font-weight: 500; text-align: left;
  color: var(--primary-text-color); background: color-mix(in srgb, var(--secondary-text-color) 10%, transparent); }
.app:hover { background: color-mix(in srgb, var(--secondary-text-color) 16%, transparent); }
.app.on { color: var(--text-primary-color, #fff); background: var(--primary-color); }
.app[disabled] { opacity: 0.4; cursor: default; }
.app span { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
ha-icon { --mdc-icon-size: 22px; flex: none; }
.hint { font-size: 12px; color: var(--secondary-text-color); padding: 0 6px; }
`;

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const isOn = (st) => st && !["off", "unavailable", "unknown"].includes(st.state);

class TvCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.entity) throw new Error("tv-card: entity is required");
    this._config = config;
    this._sig = "";
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      this.shadowRoot.addEventListener("click", (e) => {
        const b = e.target.closest("[data-id]");
        if (b && !b.disabled) this._hass.callService("media_player", "select_source", { entity_id: this._config.entity, source: b.dataset.id });
      });
    }
  }

  getCardSize() { return 6; }

  getGridOptions() { return { columns: 12, min_columns: 6, rows: 8 }; }

  set hass(hass) {
    this._hass = hass;
    if (!this._config) return;
    const c = this._config;
    const st = hass.states[c.entity];
    const on = isOn(st);
    const cur = st && st.attributes.source;
    const live = (st && st.attributes.source_list) || [];
    const sig = JSON.stringify([on, cur, live]);
    if (sig !== this._sig) {
      this._sig = sig;
      const hide = new Set(c.hide || []);
      const pinned = (c.apps || []).filter((a) => !live.length || live.includes(a.id));
      const known = new Set(pinned.map((a) => a.id));
      const rest = live.filter((n) => n && !known.has(n) && !hide.has(n)).map((n) => ({ name: n, id: n, icon: /^HDMI/i.test(n) ? "mdi:hdmi-port" : "mdi:application" }));
      const apps = [...pinned, ...rest].map((a) => `<button class="app ${on && cur === a.id ? "on" : ""}" data-id="${esc(a.id)}" ${on ? "" : "disabled"}><ha-icon icon="${esc(a.icon || "mdi:application")}"></ha-icon><span>${esc(a.name)}</span></button>`).join("");
      this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card><div id="mini"></div><div class="apps">${apps}</div>${on ? "" : `<div class="hint">Turn the TV on to launch an app.</div>`}</ha-card>`;
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
  window.customCards.push({ type: "tv-card", name: "TV card", description: "mini-media-player for the TV with an app launcher grid." });
}
