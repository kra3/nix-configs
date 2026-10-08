// Segmented control over boolean helpers: the first mode needs no entity and means "all others off"; the selected mode explains itself in one sentence.

const STYLE = `
  :host { display: block; }
  ha-card { padding: 10px 12px 12px; }
  .ti { font-size: 11px; font-weight: 700; letter-spacing: 0.6px; text-transform: uppercase; color: var(--secondary-text-color); margin: 2px 4px 8px; }
  .segs { display: grid; grid-template-columns: repeat(auto-fit, minmax(110px, 1fr)); gap: 6px; }
  .seg { font: inherit; font-size: 14px; font-weight: 600; min-height: 44px; display: flex; align-items: center; justify-content: center; gap: 8px; border-radius: 12px; border: 1px solid var(--divider-color); background: none; color: var(--secondary-text-color); cursor: pointer; }
  .seg ha-icon { --mdc-icon-size: 20px; }
  .seg.on { background: var(--c); border-color: var(--c); color: var(--text-primary-color, #fff); }
  .hint { margin: 10px 4px 2px; font-size: 13px; line-height: 1.35; color: var(--secondary-text-color); }
`;

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const TONES = { primary: "var(--primary-color)", success: "var(--success-color, #43a047)", warning: "var(--warning-color, #ffa600)", error: "var(--error-color, #db4437)", info: "var(--info-color, #039be5)" };

class ModeSwitchCard extends HTMLElement {
  setConfig(config) {
    if (!config || !Array.isArray(config.modes) || config.modes.length < 2) throw new Error("mode-switch-card: at least two modes are required");
    this._config = config;
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      this.shadowRoot.addEventListener("click", (e) => {
        const b = e.target.closest(".seg");
        if (!b || !this._hass) return;
        const i = Number(b.dataset.i);
        const mode = this._config.modes[i];
        if (i === this._current()) return;
        if (mode.confirm && !window.confirm(mode.confirm)) return;
        this._pending = i;
        this._render();
        for (const m of this._config.modes) {
          if (!m.entity) continue;
          const on = this._hass.states[m.entity] && this._hass.states[m.entity].state === "on";
          const want = m === mode;
          if (on !== want) this._hass.callService("homeassistant", want ? "turn_on" : "turn_off", { entity_id: m.entity });
        }
      });
    }
  }

  getCardSize() {
    return 2;
  }

  set hass(hass) {
    this._hass = hass;
    if (this._pending !== undefined && this._actual() === this._pending) this._pending = undefined;
    this._render();
  }

  _actual() {
    const modes = this._config.modes;
    for (let i = modes.length - 1; i > 0; i--) {
      const s = this._hass.states[modes[i].entity];
      if (s && s.state === "on") return i;
    }
    return 0;
  }

  _current() {
    return this._pending !== undefined ? this._pending : this._actual();
  }

  _render() {
    if (!this._config || !this._hass) return;
    const c = this._config;
    const cur = this._current();
    const segs = c.modes
      .map((m, i) => `<button class="seg${i === cur ? " on" : ""}" data-i="${i}" style="--c:${esc(TONES[m.tone] || m.tone || TONES.primary)}"><ha-icon icon="${esc(m.icon || "")}"></ha-icon>${esc(m.name)}</button>`)
      .join("");
    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card>${c.name ? `<div class="ti">${esc(c.name)}</div>` : ""}<div class="segs">${segs}</div><div class="hint">${esc(c.modes[cur].hint || "")}</div></ha-card>`;
  }
}

customElements.define("mode-switch-card", ModeSwitchCard);
