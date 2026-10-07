// Read-only row of entity states: icon, label and value per entry, no actions.

const STYLE = `
  :host { display: block; }
  ha-card { padding: 12px 16px; }
  .row { display: grid; grid-template-columns: repeat(var(--n), 1fr); }
  .it { display: flex; align-items: center; gap: 10px; min-width: 0; }
  .it + .it { border-left: 1px solid var(--divider-color); padding-left: 14px; margin-left: 14px; }
  ha-icon { --mdc-icon-size: 22px; color: var(--c); flex: none; }
  .lab { font-size: 11px; font-weight: 700; letter-spacing: 0.6px; text-transform: uppercase; color: var(--secondary-text-color); white-space: nowrap; }
  .val { font-size: 15px; font-weight: 600; color: var(--primary-text-color); white-space: nowrap; }
  .it.off .val { color: var(--secondary-text-color); }
`;

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

class StatusRowCard extends HTMLElement {
  setConfig(config) {
    if (!config || !Array.isArray(config.items) || !config.items.length) throw new Error("status-row-card: items are required");
    this._config = config;
    if (!this.shadowRoot) this.attachShadow({ mode: "open" });
  }

  getCardSize() {
    return 1;
  }

  set hass(hass) {
    this._hass = hass;
    this._render();
  }

  _render() {
    if (!this._config || !this._hass) return;
    const c = this._config;
    const cells = c.items
      .map((it) => {
        const s = this._hass.states[it.entity];
        const dead = !s || s.state === "unavailable" || s.state === "unknown";
        const text = dead ? "Unavailable" : (it.labels && it.labels[s.state]) || s.state.charAt(0).toUpperCase() + s.state.slice(1);
        const color = it.color || c.color || "var(--primary-color)";
        return (
          `<div class="it${dead || s.state === "off" ? " off" : ""}" style="--c:${esc(color)}"><ha-icon icon="${esc(it.icon || "")}"></ha-icon>` +
          `<div><div class="lab">${esc(it.name || (s && s.attributes.friendly_name) || "")}</div><div class="val">${esc(text)}</div></div></div>`
        );
      })
      .join("");
    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card><div class="row" style="--n:${c.items.length}">${cells}</div></ha-card>`;
  }
}

customElements.define("status-row-card", StatusRowCard);
