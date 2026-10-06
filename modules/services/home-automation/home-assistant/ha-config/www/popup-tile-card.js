// Tile that opens any stock card in an overlay popup.

const STYLE = `
  :host { display: block; }
  ha-card { cursor: pointer; }
  .tile { display: flex; align-items: center; gap: 12px; padding: 12px 14px; outline: none; }
  .icon { --mdc-icon-size: 24px; color: var(--primary-color); }
  .name { font-size: 14px; font-weight: 500; color: var(--primary-text-color); }
  .state { font-size: 12px; color: var(--secondary-text-color); }
`;

const POPUP_STYLE = `
  .ptc-overlay { position: fixed; inset: 0; z-index: 9; background: rgba(0, 0, 0, 0.6); display: flex; align-items: center; justify-content: center; padding: 16px; }
  .ptc-sheet { width: min(520px, 100%); max-height: 90vh; overflow: auto; background: var(--card-background-color, #1c1c1c); border-radius: 16px; padding: 8px 8px 12px; box-sizing: border-box; }
  .ptc-head { display: flex; justify-content: flex-end; }
  .ptc-close { background: none; border: 0; color: var(--secondary-text-color); font-size: 26px; line-height: 1; cursor: pointer; padding: 4px 10px; }
`;

class PopupTileCard extends HTMLElement {
  setConfig(config) {
    if (!config || !config.entity || !config.popup) throw new Error("popup-tile-card: entity and popup are required");
    this._config = config;
    this._html = "";
    if (!this.shadowRoot) this.attachShadow({ mode: "open" });
  }

  getCardSize() {
    return 1;
  }

  getGridOptions() {
    return { columns: 6, min_columns: 3 };
  }

  set hass(hass) {
    this._hass = hass;
    if (this._popupCard) this._popupCard.hass = hass;
    if (this._config) this._render();
  }

  _render() {
    const c = this._config;
    const s = this._hass.states[c.entity];
    const state = s ? s.state : "unavailable";
    const html = `<ha-card><div class="tile" tabindex="0"><ha-icon class="icon" icon="${c.icon || "mdi:format-list-bulleted"}"></ha-icon><div><div class="name"></div><div class="state"></div></div></div></ha-card>`;
    if (html !== this._html) {
      this._html = html;
      this.shadowRoot.innerHTML = `<style>${STYLE}</style>${html}`;
      this.shadowRoot.querySelector("ha-card").addEventListener("click", () => this._open());
    }
    this.shadowRoot.querySelector(".name").textContent = c.name || (s && s.attributes.friendly_name) || c.entity;
    this.shadowRoot.querySelector(".state").textContent = c.unit ? `${state} ${c.unit}` : state;
  }

  async _open() {
    if (this._overlay) return;
    if (!document.getElementById("ptc-style")) {
      const st = document.createElement("style");
      st.id = "ptc-style";
      st.textContent = POPUP_STYLE;
      document.head.appendChild(st);
    }
    const helpers = await window.loadCardHelpers();
    const card = await helpers.createCardElement(this._config.popup);
    card.hass = this._hass;
    const ov = document.createElement("div");
    ov.className = "ptc-overlay";
    ov.innerHTML = `<div class="ptc-sheet" role="dialog" aria-modal="true"><div class="ptc-head"><button class="ptc-close" aria-label="Close">×</button></div></div>`;
    ov.querySelector(".ptc-sheet").appendChild(card);
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
    ov.querySelector(".ptc-close").addEventListener("click", close);
    document.addEventListener("keydown", onKey);
    document.body.appendChild(ov);
    this._overlay = ov;
    this._popupCard = card;
  }
}

if (typeof customElements !== "undefined" && !customElements.get("popup-tile-card")) {
  customElements.define("popup-tile-card", PopupTileCard);
  window.customCards = window.customCards || [];
  window.customCards.push({
    type: "popup-tile-card",
    name: "Popup tile card",
    description: "Tile that opens any card in a popup.",
  });
}
