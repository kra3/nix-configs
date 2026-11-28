import { sheet, tokens } from "./tokens.js?v=10";
import { mount } from "./dom.js?v=10";
import { pickSet } from "./layout.js?v=10";
import { situation, inputFromHass, DEFAULT_CONFIG } from "./situation.js?v=10";

const own = sheet(`
:host { display: block; }
:host([hidden]) { display: none; }
.head { margin: 0 0 var(--ds-space-3); font: 600 clamp(17px, 2vw + 9px, 22px)/1.3 var(--ds-font); color: var(--primary-text-color);
  transition: opacity var(--ds-motion-state) linear; text-wrap: balance; }
.head.fade { opacity: 0; }
.head[hidden] { display: none; }
.set { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 300px), 1fr)); gap: var(--ds-gap); align-items: start; }
.set > * { min-width: 0; animation: ds-stack-in var(--ds-motion-sheet) var(--ds-ease) both; animation-delay: calc(var(--i, 0) * 40ms); }
.set > [hidden] { display: none !important; }
.set > .full { grid-column: 1 / -1; }
.set.out > * { animation: ds-stack-out var(--ds-motion-state) linear both; animation-delay: 0ms; }
.err { padding: var(--ds-space-3); color: var(--secondary-text-color); font: var(--ds-body); }
@keyframes ds-stack-in { from { opacity: 0; transform: translateY(12px); } }
@keyframes ds-stack-out { to { opacity: 0; transform: translateY(-6px); } }
@media (prefers-reduced-motion: reduce) { .set > *, .set.out > * { animation: none; } }
`);

const FADE = 150;
const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches;
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

class SituationStackCard extends HTMLElement {
  constructor() {
    super();
    mount(this, tokens, own).innerHTML = `<p class="head" aria-live="polite" hidden></p><div class="set"></div>`;
    this._head = this.shadowRoot.querySelector(".head");
    this._box = this.shadowRoot.querySelector(".set");
    this._seq = 0;
  }

  setConfig(c) {
    if (!c || (!c.situations && !c.default)) throw new Error("situation-stack-card: situations or default is required");
    this._config = c;
    const s = { ...DEFAULT_CONFIG, ...c.situation_config };
    this._sit = c.situation_config;
    this._ids = [
      s.sun, s.attention, s.openings, s.guestEntity, ...s.media, ...Object.values(s.lights), ...Object.values(s.laundry),
      ...Object.values(s.people).flatMap((p) => [p.person, p.eta, p.arriving, p.justLeft]),
    ].filter(Boolean);
    this._sig = null;
    this._setId = undefined;
    this._text = undefined;
  }

  getCardSize() { return 4; }
  getGridOptions() { return { columns: "full", min_columns: 6 }; }

  disconnectedCallback() { clearTimeout(this._ht); }

  set hass(h) {
    this._hass = h;
    if (!this._config) return;
    const sig = this._ids.map((id) => h.states[id]);
    const minute = Math.floor(Date.now() / 6e4);
    const uid = h.user?.id;
    if (!this._sig || minute !== this._minute || uid !== this._uid || sig.some((s, i) => s !== this._sig[i])) {
      this._sig = sig; this._minute = minute; this._uid = uid;
      this._update(h);
    }
    for (const el of this._box.children) el.hass = h;
  }

  _update(h) {
    let s;
    try { s = situation(inputFromHass(h, h.user?.id, this._sit)); } catch (e) { console.error(e); s = { key: "default", headline: "" }; }
    this._say(this._config.headline === false ? "" : s.headline);
    const set = pickSet(this._config.situations, s.key, this._config.default);
    if (set.id !== this._setId) {
      this._setId = set.id;
      this._render(set.cards);
    }
  }

  _say(text) {
    if (text === this._text) return;
    const first = this._text === undefined;
    this._text = text;
    const apply = () => { this._head.textContent = text; this._head.hidden = !text; this._head.classList.remove("fade"); };
    clearTimeout(this._ht);
    if (first || reduced() || !this._head.textContent) return apply();
    this._head.classList.add("fade");
    this._ht = setTimeout(apply, FADE);
  }

  async _make(c) {
    let el;
    try {
      if (customElements.get("hui-card")) {
        el = document.createElement("hui-card");
        el.config = c;
      } else {
        el = await (await window.loadCardHelpers()).createCardElement(c);
      }
    } catch (e) {
      console.error(e);
      el = document.createElement("div");
      el.className = "err";
      el.textContent = "This card couldn’t load.";
    }
    const cols = c.grid_options?.columns;
    if (cols === "full" || cols >= 12) el.classList.add("full");
    if (this._hass) el.hass = this._hass;
    return el;
  }

  async _render(cards) {
    const seq = ++this._seq;
    if (this._box.children.length && !reduced()) {
      this._box.classList.add("out");
      await wait(FADE);
    }
    const els = await Promise.all(cards.map((c) => this._make(c)));
    if (seq !== this._seq) return;
    els.forEach((e, i) => e.style.setProperty("--i", Math.min(i, 8)));
    this._box.classList.remove("out");
    this._box.replaceChildren(...els);
  }
}

if (!customElements.get("situation-stack-card")) {
  customElements.define("situation-stack-card", SituationStackCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "situation-stack-card", name: "Situation stack", description: "Headline and card set chosen by who is home and the time of day." });
}
