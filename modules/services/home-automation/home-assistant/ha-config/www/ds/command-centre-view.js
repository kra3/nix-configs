import { sheet, tokens } from "./tokens.js?v=6";
import { primitives } from "./primitives.js?v=6";
import { mount } from "./dom.js?v=6";
import { layoutMode, partition, columnCount, sectionSpan, detailConfig } from "./layout.js?v=6";

const own = sheet(`
:host { display: grid; gap: var(--ds-gap); padding: var(--ds-space-4); box-sizing: border-box; align-items: start;
  grid-template-columns: 260px minmax(0, 1fr); color: var(--primary-text-color); }
:host([data-mode="wide"][open]) { grid-template-columns: 260px minmax(0, 1fr) 360px; }
:host([data-mode="narrow"]) { grid-template-columns: minmax(0, 1fr); padding: var(--ds-space-2); }
[hidden] { display: none !important; }
.rail { display: flex; flex-direction: column; gap: var(--ds-gap); min-width: 0; }
.col { min-width: 0; }
.badges { display: flex; flex-wrap: wrap; gap: var(--ds-space-2); margin-bottom: var(--ds-gap); }
.main { display: grid; grid-auto-flow: dense; gap: var(--ds-gap); min-width: 0; }
.pane { background: var(--card-background-color); color: var(--primary-text-color); outline: 0; box-sizing: border-box; overflow: hidden;
  animation: ds-in var(--ds-motion-sheet) var(--ds-ease); }
:host([data-mode="wide"]) .pane { position: sticky; top: var(--ds-space-4); max-height: calc(100vh - 2 * var(--ds-space-4)); border-radius: var(--ds-radius-tile); }
:host(:not([data-mode="wide"])) .pane { position: fixed; z-index: 11; }
:host([data-mode="mid"]) .pane { top: 0; right: 0; bottom: 0; width: min(420px, 100vw); animation-name: ds-in-x; }
:host([data-mode="narrow"]) .pane { left: 0; right: 0; bottom: 0; max-height: 85vh; border-radius: var(--ds-radius-sheet) var(--ds-radius-sheet) 0 0; }
.scrim { position: fixed; inset: 0; z-index: 10; background: color-mix(in srgb, var(--primary-text-color) 40%, transparent); }
.pane:not([hidden]) { display: flex; flex-direction: column; }
:host([data-mode="narrow"]) .pane { min-height: 40vh; }
.body { flex: 1; overflow: auto; overscroll-behavior: contain; padding: 0 var(--ds-space-4) var(--ds-space-4); }
:host([data-mode="narrow"]) .body { padding-bottom: calc(var(--ds-space-4) + env(safe-area-inset-bottom)); }
.head { display: flex; justify-content: flex-end; padding: var(--ds-space-2); }
.close { width: var(--ds-touch); height: var(--ds-touch); border: 0; border-radius: 999px; cursor: pointer; font-size: 20px; touch-action: manipulation;
  background: transparent; color: var(--primary-text-color); }
.close:hover { background: color-mix(in srgb, var(--primary-text-color) 12%, transparent); }
.close:focus-visible { outline: 2px solid var(--primary-color); outline-offset: -2px; }
@keyframes ds-in { from { opacity: 0; transform: translateY(16px); } }
@keyframes ds-in-x { from { opacity: 0; transform: translateX(16px); } }
`);

class CommandCentre extends HTMLElement {
  constructor() {
    super();
    mount(this, tokens, primitives, own);
    this.shadowRoot.innerHTML = `<div class="rail"></div><div class="col"><div class="badges" hidden></div><div class="main"></div></div><aside class="pane" role="dialog" aria-label="Details" tabindex="-1" hidden></aside><div class="scrim" hidden></div>`;
    const $ = (s) => this.shadowRoot.querySelector(s);
    this._rail = $(".rail"); this._main = $(".main"); this._badges = $(".badges"); this._pane = $(".pane"); this._scrim = $(".scrim");
    this._max = 4; this._sections = []; this._hass = undefined; this._card = null; this._openSeq = 0;
    this._ro = new ResizeObserver(() => this._layout());
    this.addEventListener("section-visibility-changed", () => this._layout(), true);
    this.addEventListener("ll-custom", (ev) => this._open(ev));
    this.addEventListener("keydown", (ev) => { if (ev.key === "Escape") this._close(); });
    this._scrim.addEventListener("click", () => this._close());
    this._onPop = () => this._close(true);
  }

  connectedCallback() {
    this._ro.observe(this); this._ro.observe(this._main);
    window.addEventListener("popstate", this._onPop);
  }
  disconnectedCallback() {
    this._ro.disconnect();
    this._close(true);
    window.removeEventListener("popstate", this._onPop);
  }

  setConfig(c) { this._max = c?.max_columns ?? 4; this._layout(); }
  get sections() { return this._sections; }
  set sections(v) {
    this._sections = v || [];
    this._place();
  }
  set badges(v) { this._badges.replaceChildren(...(v || [])); this._badges.hidden = !v?.length; }
  get hass() { return this._hass; }
  set hass(h) { this._hass = h; if (this._card) this._card.hass = h; }

  _place() {
    const { rail, main } = partition(this._sections);
    this._rail.replaceChildren(...rail);
    this._main.replaceChildren(...main);
    this._layout();
  }

  _layout() {
    this.dataset.mode = layoutMode(this.getBoundingClientRect().width);
    const cols = columnCount(this._main.clientWidth, this._max);
    this._main.style.gridTemplateColumns = `repeat(${cols}, minmax(0, 1fr))`;
    for (const s of this._main.children) if (!s.hidden) s.style.gridColumn = "span " + sectionSpan(s, cols);
    this._scrim.hidden = !this._isOpen() || this.dataset.mode === "wide";
    const modal = this._isOpen() && this.dataset.mode !== "wide";
    this._pane.setAttribute("aria-modal", String(this.dataset.mode !== "wide"));
    for (const e of [this._rail, this._main, this._badges]) e.toggleAttribute("inert", modal);
  }

  _isOpen() { return !this._pane.hidden; }

  async _open(ev) {
    const cfg = detailConfig(ev);
    if (!cfg) return;
    ev.stopPropagation();
    ev.preventDefault();
    const seq = ++this._openSeq;
    if (!this._isOpen()) {
      let a = document.activeElement;
      while (a?.shadowRoot?.activeElement) a = a.shadowRoot.activeElement;
      this._restore = a ?? ev.composedPath()[0];
    }
    let body = document.createElement("div");
    body.className = "body";
    this._card = null;
    try {
      const h = await window.loadCardHelpers();
      const el = await h.createCardElement(cfg);
      el.hass = this._hass;
      this._card = el;
      body.append(el);
    } catch (e) {
      console.error(e);
      body.textContent = "Couldn’t open this detail. Close and try again.";
    }
    if (seq !== this._openSeq) return;
    const wasOpen = this._isOpen();
    const head = document.createElement("div");
    head.className = "head";
    head.innerHTML = `<button class="close" aria-label="Close"><span aria-hidden="true">✕</span></button>`;
    head.firstChild.addEventListener("click", () => this._close());
    this._pane.replaceChildren(head, body);
    this._pane.hidden = false;
    this.toggleAttribute("open", true);
    this._layout();
    this._pane.focus();
    if (!wasOpen) history.pushState({ ccDetail: true }, "");
  }

  _close(fromPop) {
    this._openSeq++;
    if (!this._isOpen()) return;
    this._pane.hidden = true;
    this._card = null;
    this.toggleAttribute("open", false);
    this._layout();
    this._restore?.focus?.();
    if (!fromPop && history.state?.ccDetail) history.back();
  }
}
customElements.define("command-centre", CommandCentre);
