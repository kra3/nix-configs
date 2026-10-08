// Wrapping row of entity states: icon, label, value and an optional hint per entry; `colors` maps a state (or the value of the attribute named by `color_attribute`) to a theme tone (success, warning, error, info, inactive, primary) with `other` as the fallback; an entry is tappable only when it sets `tap: toggle`.

const STYLE = `
  :host { display: block; }
  ha-card { padding: 8px 10px; }
  .row { display: grid; grid-template-columns: repeat(auto-fit, minmax(var(--min), 1fr)); gap: 2px 8px; }
  .it { display: flex; align-items: flex-start; gap: 10px; min-width: 0; padding: 8px 10px; border-radius: 10px; }
  .it.tap { cursor: pointer; min-height: 44px; }
  .it.tap:hover { background: var(--secondary-background-color); }
  ha-icon { --mdc-icon-size: 22px; color: var(--c); flex: none; margin-top: 1px; }
  .lab { font-size: 11px; font-weight: 700; letter-spacing: 0.6px; text-transform: uppercase; color: var(--secondary-text-color); }
  .val { font-size: 15px; font-weight: 600; color: var(--primary-text-color); }
  .hint { font-size: 12px; line-height: 1.3; color: var(--secondary-text-color); margin-top: 1px; }
  .it.off .val { color: var(--secondary-text-color); }
`;

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const TONES = { primary: "var(--primary-color)", success: "var(--success-color, #43a047)", warning: "var(--warning-color, #ffa600)", error: "var(--error-color, #db4437)", info: "var(--info-color, #039be5)", inactive: "var(--state-inactive-color, var(--secondary-text-color))" };
const tone = (v) => TONES[v] || v;

class StatusRowCard extends HTMLElement {
  setConfig(config) {
    if (!config || !Array.isArray(config.items) || !config.items.length) throw new Error("status-row-card: items are required");
    this._config = config;
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      this.shadowRoot.addEventListener("click", (e) => {
        const el = e.target.closest(".it.tap");
        const it = el && this._config.items[Number(el.dataset.i)];
        if (!it || !this._hass) return;
        if (it.confirm && !window.confirm(it.confirm)) return;
        this._hass.callService("homeassistant", "toggle", { entity_id: it.entity });
      });
    }
  }

  getCardSize() {
    return 2;
  }

  set hass(hass) {
    this._hass = hass;
    this._render();
  }

  _render() {
    if (!this._config || !this._hass) return;
    const c = this._config;
    const cells = c.items
      .map((it, i) => {
        const s = this._hass.states[it.entity];
        const dead = !s || s.state === "unavailable" || s.state === "unknown";
        const text = dead ? "Unavailable" : (it.labels && it.labels[s.state]) || s.state.charAt(0).toUpperCase() + s.state.slice(1);
        const hint = dead ? "" : (it.hints && it.hints[s.state]) || it.hint || "";
        const base = it.color || c.color || "primary";
        const color = tone(dead ? "inactive" : (it.colors && (it.colors[it.color_attribute ? s.attributes[it.color_attribute] : s.state] || it.colors.other)) || (s.state === "off" ? "inactive" : base));
        const tap = it.tap === "toggle" && !dead;
        return (
          `<div class="it${dead || s.state === "off" ? " off" : ""}${tap ? " tap" : ""}" data-i="${i}" style="--c:${esc(color)}"><ha-icon icon="${esc(it.icon || "")}"></ha-icon>` +
          `<div><div class="lab">${esc(it.name || (s && s.attributes.friendly_name) || "")}</div><div class="val">${esc(text)}</div>${hint ? `<div class="hint">${esc(hint)}</div>` : ""}</div></div>`
        );
      })
      .join("");
    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card><div class="row" style="--min:${esc(c.min_width || "170px")}">${cells}</div></ha-card>`;
  }
}

customElements.define("status-row-card", StatusRowCard);
