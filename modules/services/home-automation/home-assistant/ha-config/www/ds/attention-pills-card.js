import { sheet, tokens } from "./tokens.js?v=10";
import { primitives } from "./primitives.js?v=10";
import { SEVERITY, mount } from "./dom.js?v=10";

const own = sheet(`
:host { display: block; }
:host([hidden]) { display: none; }
.pills { display: flex; flex-wrap: wrap; gap: var(--ds-space-2); }
@media (max-width: 819px) { .pills { flex-wrap: nowrap; overflow-x: auto; scrollbar-width: none; } .pill { flex: none; white-space: nowrap; max-width: none; } .pills > [role=listitem] { flex: none; } }
.pill { min-height: var(--ds-touch); border: 0; cursor: pointer; text-align: left; touch-action: manipulation; max-width: 100%; }
.pill ha-icon { --mdc-icon-size: 16px; flex: none; }
.pill span { overflow-wrap: anywhere; }
`);

class AttentionPillsCard extends HTMLElement {
  constructor() {
    super();
    mount(this, tokens, primitives, own).innerHTML = `<div class="pills" role="list"></div>`;
  }

  setConfig(c) {
    if (!c?.entity) throw new Error("attention-pills-card: entity is required");
    this._config = c;
    this.hidden = true;
  }

  getCardSize() { return 1; }
  getGridOptions() { return { columns: "full", min_columns: 3 }; }

  set hass(h) {
    this._hass = h;
    const items = h.states[this._config.entity]?.attributes?.items;
    const list = Array.isArray(items) ? items : [];
    const key = JSON.stringify(list);
    if (key !== this._key) {
      this._key = key;
      const box = this.shadowRoot.querySelector(".pills");
      box.replaceChildren(...list.map((i) => this._pill(i)));
    }
    this.hidden = list.length === 0;
  }

  _pill(i) {
    const li = document.createElement("span");
    li.setAttribute("role", "listitem");
    const b = document.createElement("button");
    b.className = "chip chip--tint pill";
    b.style.setProperty("--tint", SEVERITY[i.severity] || SEVERITY.info);
    const icon = document.createElement("ha-icon");
    icon.setAttribute("icon", i.icon || "mdi:alert-circle-outline");
    const label = document.createElement("span");
    label.textContent = i.label;
    b.append(icon, label);
    b.addEventListener("click", () => {
      if (!i.path) return;
      history.pushState(null, "", i.path);
      window.dispatchEvent(new Event("location-changed"));
    });
    li.append(b);
    return li;
  }
}

if (!customElements.get("attention-pills-card")) {
  customElements.define("attention-pills-card", AttentionPillsCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "attention-pills-card", name: "Attention pills", description: "Pills for sensor.attention items." });
}
