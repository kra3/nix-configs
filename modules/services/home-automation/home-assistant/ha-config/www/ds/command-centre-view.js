import { sheet, tokens } from "./tokens.js?v=12";
import { primitives } from "./primitives.js?v=12";
import { mount } from "./dom.js?v=12";
import { layoutMode, partition, columnCount, sectionSpan, detailConfig } from "./layout.js?v=12";

const own = sheet(`
:host { display: grid; gap: var(--ds-gap); padding: var(--ds-space-4); box-sizing: border-box; align-items: start;
  grid-template-columns: 260px minmax(0, 1fr); color: var(--primary-text-color); }
:host([data-mode="wide"][open]) { grid-template-columns: 260px minmax(0, 1fr) 360px; }
:host([data-mode="narrow"]) { grid-template-columns: minmax(0, 1fr); padding: var(--ds-space-2); }
:host([data-norail]) { grid-template-columns: minmax(0, 1fr); }
:host([data-norail][data-mode="wide"][open]) { grid-template-columns: minmax(0, 1fr) 360px; }
[hidden] { display: none !important; }
.rail > *, .lead > * { min-width: 0; }
.railbar { display: flex; align-items: center; gap: var(--ds-space-2); width: 100%; min-height: var(--ds-touch); box-sizing: border-box; padding: 0 var(--ds-space-3); border: 0; border-radius: var(--ds-radius-tile);
  background: var(--card-background-color); color: var(--primary-text-color); font: var(--ds-label); text-align: left; cursor: pointer; touch-action: manipulation; }
.railbar:focus-visible { outline: 2px solid var(--primary-color); outline-offset: 2px; }
.railbar ha-icon { --mdc-icon-size: 18px; flex: none; }
.railbar .n { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.railbar .n.warn, .railbar .n.warn ha-icon { color: var(--warning-color); }
.railbar .a { color: var(--secondary-text-color); white-space: nowrap; }
.railbar .chev { transition: transform var(--ds-motion-state) var(--ds-ease); }
.railbar[aria-expanded="true"] .chev { transform: rotate(180deg); }
.lead { display: flex; flex-direction: column; min-width: 0; }
.rail { display: flex; flex-direction: column; gap: var(--ds-gap); min-width: 0; }
.col { min-width: 0; }
.badges { display: flex; flex-wrap: wrap; gap: var(--ds-space-2); margin-bottom: var(--ds-gap); }
:host([data-mode="narrow"]) .badges { flex-wrap: nowrap; overflow-x: auto; scrollbar-width: none; }
:host([data-mode="narrow"]) .badges > * { flex: none; }
.main { display: grid; grid-auto-flow: dense; grid-auto-rows: 8px; column-gap: var(--ds-gap); row-gap: 0; min-width: 0; }
.main > * { align-self: start; margin-bottom: var(--ds-gap); }
:host(:not([data-mode="narrow"])) .rail { position: sticky; top: calc(var(--header-height, 56px) + var(--ds-space-4)); max-height: calc(100vh - var(--header-height, 56px) - 2 * var(--ds-space-4)); overflow-x: hidden; overflow-y: auto; overscroll-behavior: contain; }
.pane { background: var(--card-background-color); color: var(--primary-text-color); outline: 0; box-sizing: border-box; overflow: hidden;
  animation: ds-in var(--ds-motion-sheet) var(--ds-ease); }
:host([data-mode="wide"]) .pane { position: sticky; top: var(--ds-space-4); max-height: calc(100vh - 2 * var(--ds-space-4)); border-radius: var(--ds-radius-tile); }
:host(:not([data-mode="wide"])) .pane { position: fixed; z-index: 11; }
:host([data-mode="mid"]) .pane { top: 0; right: 0; bottom: 0; width: min(420px, 100vw); animation-name: ds-in-x; }
:host([data-mode="narrow"]) .pane { left: 0; right: 0; bottom: 0; max-height: 85vh; border-radius: var(--ds-radius-sheet) var(--ds-radius-sheet) 0 0; }
.scrim { position: fixed; inset: 0; z-index: 10; background: color-mix(in srgb, black 55%, transparent); }
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
@keyframes ds-sheet-in { from { transform: translateY(100%); } }
:host([data-mode="narrow"]) .pane { animation: ds-sheet-in 300ms cubic-bezier(.34, 1.45, .64, 1); }
@media (prefers-reduced-motion: reduce) { .pane { animation: none !important; } }
`);

class CommandCentre extends HTMLElement {
  constructor() {
    super();
    mount(this, tokens, primitives, own);
    this.shadowRoot.innerHTML = `<div class="lead" hidden></div><button class="railbar" aria-expanded="false" hidden></button><div class="rail"></div><div class="col"><div class="badges" hidden></div><div class="main"></div></div><aside class="pane" role="dialog" aria-label="Details" tabindex="-1" hidden></aside><div class="scrim" hidden></div>`;
    const $ = (s) => this.shadowRoot.querySelector(s);
    this._lead = $(".lead"); this._leadEls = []; this._rail = $(".rail"); this._bar = $(".railbar"); this._railOpen = false; this._cfg = {}; this._main = $(".main"); this._badges = $(".badges"); this._pane = $(".pane"); this._scrim = $(".scrim");
    this._max = 4; this._sections = []; this._hass = undefined; this._card = null; this._openSeq = 0;
    this._ro = new ResizeObserver(() => this._layout());
    this._watched = new Set();
    this.addEventListener("section-visibility-changed", () => this._layout(), true);
    this.addEventListener("ll-custom", (ev) => this._open(ev));
    this.addEventListener("keydown", (ev) => { if (ev.key === "Escape") this._close(); });
    this._scrim.addEventListener("click", () => this._close());
    this._bar.addEventListener("click", () => { this._railOpen = !this._railOpen; this._layout(); });
    this._onPop = () => this._close(true);
  }

  connectedCallback() {
    this._ro.observe(this); this._ro.observe(this._main);
    for (const s of this._watched) this._ro.observe(s);
    window.addEventListener("popstate", this._onPop);
  }
  disconnectedCallback() {
    this._ro.disconnect();
    this._close(true);
    window.removeEventListener("popstate", this._onPop);
  }

  setConfig(c) { this._cfg = c ?? {}; this._max = c?.max_columns ?? 4; this._layout(); }
  get sections() { return this._sections; }
  set sections(v) {
    this._sections = v || [];
    this._place();
  }
  set badges(v) { this._badges.replaceChildren(...(v || [])); this._badges.hidden = !v?.length; }
  get hass() { return this._hass; }
  set hass(h) { this._hass = h; this._summary(); if (this._card) this._card.hass = h; }

  _place() {
    const { rail, main, lead } = partition(this._sections);
    this._rail.replaceChildren(...rail);
    this._main.replaceChildren(...main);
    this._leadEls = lead;
    this._lead.replaceChildren();
    for (const s of this._watched) if (!main.includes(s) && !lead.includes(s)) { this._ro.unobserve(s); this._watched.delete(s); }
    for (const s of [...lead, ...main]) if (!this._watched.has(s)) { this._ro.observe(s); this._watched.add(s); }
    this._layout();
  }

  _summary() {
    const h = this._hass;
    if (!h || this._bar.hidden) return;
    const n = Number(h.states["sensor.attention"]?.state) || 0;
    const a = (h.states["alarm_control_panel.vasudha_secure"]?.state ?? "").replace(/_/g, " ");
    const key = n + "|" + a;
    if (key === this._barKey) return;
    this._barKey = key;
    this._bar.innerHTML = `<span class="n ${n ? "warn" : ""}"><ha-icon icon="${n ? "mdi:alert-circle-outline" : "mdi:check-circle-outline"}"></ha-icon> ${n ? `${n} need${n === 1 ? "s" : ""} attention` : "All clear"}</span>${a ? `<span class="a">Alarm ${a}</span>` : ""}<ha-icon class="chev" icon="mdi:chevron-down"></ha-icon>`;
  }

  _layout() {
    this.dataset.mode = layoutMode(this.getBoundingClientRect().width);
    const folded = this.dataset.mode === "narrow" && this._cfg.cc_rail === "collapsed";
    this._bar.hidden = !folded;
    this._bar.setAttribute("aria-expanded", String(this._railOpen));
    const norail = !this._rail.children.length;
    this.toggleAttribute("data-norail", norail);
    this._rail.hidden = norail || (folded && !this._railOpen);
    if (norail) this._bar.hidden = true;
    this._summary();
    const to = this.dataset.mode === "narrow" ? this._lead : this._main;
    if (this._leadEls.some((s) => s.parentNode !== to)) {
      if (to === this._main) this._main.prepend(...this._leadEls); else this._lead.replaceChildren(...this._leadEls);
    }
    this._lead.hidden = to !== this._lead || this._leadEls.every((s) => s.hidden);
    const cols = columnCount(this._main.clientWidth, this._max);
    this._main.style.gridTemplateColumns = `repeat(${cols}, minmax(0, 1fr))`;
    for (const s of this._main.children) if (!s.hidden) {
      s.style.gridColumn = "span " + sectionSpan(s, cols);
      s.style.gridRow = "span " + Math.ceil((s.offsetHeight + parseFloat(getComputedStyle(s).marginBottom)) / 8);
    }
    this._scrim.hidden = !this._isOpen() || this.dataset.mode === "wide";
    const modal = this._isOpen() && this.dataset.mode !== "wide";
    this._pane.setAttribute("aria-modal", String(this.dataset.mode !== "wide"));
    for (const e of [this._lead, this._bar, this._rail, this._main, this._badges]) e.toggleAttribute("inert", modal);
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
