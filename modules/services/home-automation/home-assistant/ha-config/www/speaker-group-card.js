// One speaker as a tile: a mini-media-player, or a "playing with" placeholder while it is grouped under another leader.

const STYLE = `
:host { display: block; height: 100%; min-width: 0; --mini-media-player-artwork-opacity: 0.35; }
ha-card { position: relative; box-sizing: border-box; height: 100%; min-width: 0; overflow: hidden; padding: 6px 10px; display: flex; flex-direction: column; justify-content: center; gap: 8px; }
#mini { min-width: 0; max-width: 100%; border-radius: 12px; overflow: hidden; }
.mwrap { position: relative; min-width: 0; }
.bi { position: absolute; top: 8px; right: 56px; z-index: 1; display: inline-flex; align-items: center; justify-content: center; width: 40px; height: 40px; padding: 0; border: 0; border-radius: 50%; cursor: pointer;
  color: var(--primary-text-color); background: none; }
.bi:hover { background: color-mix(in srgb, var(--primary-text-color) 14%, transparent); }
.folded { display: flex; flex-direction: column; align-items: center; gap: 10px; text-align: center; color: var(--secondary-text-color); font-size: 14px; }
.folded b { color: var(--primary-text-color); font-size: 16px; }
.btn { display: inline-flex; align-items: center; gap: 6px; height: 40px; padding: 0 14px; border: 0; border-radius: 20px; cursor: pointer; font: inherit; font-size: 13px;
  color: var(--primary-color); background: color-mix(in srgb, var(--primary-color) 16%, transparent); }
ha-icon { --mdc-icon-size: 22px; }
`;

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

class SpeakerTile extends HTMLElement {
  setConfig(config) {
    if (!config || !config.entity) throw new Error("speaker-group-card: entity is required");
    this._config = config;
    this._sig = "";
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      this.shadowRoot.addEventListener("click", (e) => {
        const t = e.target.closest("[data-a]");
        if (!t) return;
        if (t.dataset.a === "browse") this.dispatchEvent(new CustomEvent("hass-more-info", { detail: { entityId: this._config.entity }, bubbles: true, composed: true }));
        else if (t.dataset.a === "ungroup") this._hass.callService("media_player", "unjoin", { entity_id: this._config.entity });
      });
    }
    const c = config;
    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card>
      <div class="mwrap"><button class="bi" data-a="browse" title="Browse media"><ha-icon icon="mdi:folder-music"></ha-icon></button>
      <div id="mini"></div></div><div class="folded" hidden></div></ha-card>`;
    this._mini = document.createElement("mini-media-player");
    try {
      this._mini.setConfig({
        type: "custom:mini-media-player",
        entity: c.entity,
        name: c.name,
        icon: c.icon,
        artwork: "cover",
        info: "scroll",
        group: true,
        hide: { power: true },
        speaker_group: { platform: "media_player", entities: (c.peers || []).map((p) => ({ entity_id: p.entity, name: p.name })) },
      });
    } catch (err) {
      this.shadowRoot.getElementById("mini").textContent = `speaker-group-card: ${err.message}`;
    }
    this.shadowRoot.getElementById("mini").appendChild(this._mini);
  }

  getCardSize() { return 4; }

  getGridOptions() { return { columns: 12, min_columns: 6, rows: 2 }; }

  set hass(hass) {
    this._hass = hass;
    if (!this._config) return;
    const c = this._config;
    const st = hass.states[c.entity];
    const members = (st && st.attributes.group_members) || [];
    const lead = members.length > 1 && members[0] !== c.entity ? members[0] : "";
    const sig = JSON.stringify(lead);
    if (sig !== this._sig) {
      this._sig = sig;
      const root = this.shadowRoot;
      const peer = (c.peers || []).find((p) => p.entity === lead);
      root.querySelector(".mwrap").hidden = !!lead;
      const f = root.querySelector(".folded");
      f.hidden = !lead;
      f.innerHTML = lead ? `<b>${esc(c.name)}</b><span>Playing with ${esc(peer ? peer.name : lead)}</span><button class="btn" data-a="ungroup"><ha-icon icon="mdi:link-off"></ha-icon>Ungroup</button>` : "";
    }
    this._mini.hass = hass;
  }
}

if (typeof customElements !== "undefined" && !customElements.get("speaker-group-card")) {
  customElements.define("speaker-group-card", SpeakerTile);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "speaker-group-card", name: "Speaker tile", description: "A speaker as a mini-media-player tile with a grouped placeholder." });
}
