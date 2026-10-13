// Room speakers as mini-media-players; a speaker grouped under another leader is folded into the leader's card.

const STYLE = `
:host { display: block; --mini-media-player-artwork-opacity: 0.5; }
.wrap { display: flex; flex-direction: column; gap: 8px; }
.hint { font-size: 12px; color: var(--secondary-text-color); padding: 2px 6px; }
`;

class SpeakerGroupCard extends HTMLElement {
  setConfig(config) {
    if (!config || !Array.isArray(config.speakers) || !config.speakers.length) {
      throw new Error("speaker-group-card: speakers is required");
    }
    this._config = config;
    this._els = {};
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      this.shadowRoot.innerHTML = `<style>${STYLE}</style><div class="wrap"></div>`;
    }
    this._wrap = this.shadowRoot.querySelector(".wrap");
    this._wrap.textContent = "";
    this._hint = document.createElement("div");
    this._hint.className = "hint";
    this._hint.hidden = true;
    this._wrap.appendChild(this._hint);
    this._sig = "";
  }

  getCardSize() { return 3; }

  getGridOptions() { return { columns: 12, min_columns: 6 }; }

  _miniConfig(s) {
    const c = this._config;
    const peers = [c.living, ...c.speakers].filter((p) => p && p.entity !== s.entity);
    return {
      type: "custom:mini-media-player",
      entity: s.entity,
      name: s.name,
      icon: s.icon,
      artwork: "cover",
      info: "scroll",
      hide: { power: true },
      speaker_group: { platform: "media_player", entities: peers.map((p) => ({ entity_id: p.entity, name: p.name })) },
    };
  }

  set hass(hass) {
    this._hass = hass;
    if (!this._config) return;
    const c = this._config;
    const followers = {};
    for (const s of c.speakers) {
      const st = hass.states[s.entity];
      const members = (st && st.attributes.group_members) || [];
      if (members.length > 1 && members[0] !== s.entity) followers[s.entity] = members[0];
    }
    const sig = JSON.stringify(followers);
    for (const s of c.speakers) {
      let el = this._els[s.entity];
      if (!el) {
        el = this._els[s.entity] = document.createElement("mini-media-player");
        el.setConfig(this._miniConfig(s));
        this._wrap.appendChild(el);
      }
      el.style.display = followers[s.entity] ? "none" : "";
      el.hass = hass;
    }
    if (sig === this._sig) return;
    this._sig = sig;
    const label = (id) => (id === (c.living || {}).entity ? c.living.name : (c.speakers.find((s) => s.entity === id) || {}).name || id);
    const folded = c.speakers.filter((s) => followers[s.entity]);
    this._hint.hidden = !folded.length;
    this._hint.textContent = folded.length ? `${folded.map((s) => s.name).join(", ")} playing with ${label(followers[folded[0].entity])}` : "";
  }
}

if (typeof customElements !== "undefined" && !customElements.get("speaker-group-card")) {
  customElements.define("speaker-group-card", SpeakerGroupCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "speaker-group-card", name: "Speaker group card", description: "Room speakers as mini-media-players, folded into the group leader when grouped." });
}
