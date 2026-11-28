import { sheet } from "./tokens.js?v=9";

export const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
export const SEVERITY = { error: "var(--error-color)", warning: "var(--warning-color)", info: "var(--info-color)" };
export const num = (s) => (s?.state == null || s.state === "" || isNaN(s.state) ? null : Number(s.state));
export const mount = (el, ...sheets) => { const r = el.attachShadow({ mode: "open" }); r.adoptedStyleSheets = sheets; return r; };
// Returns true when a handler (the command-centre pane) consumed the drill.
export const drill = (el, cc_detail) => !el.dispatchEvent(new CustomEvent("ll-custom", { detail: { action: "fire-dom-event", cc_detail }, bubbles: true, composed: true, cancelable: true }));
export const moreInfo = (el, entityId) => el.dispatchEvent(new CustomEvent("hass-more-info", { detail: { entityId }, bubbles: true, composed: true }));
export const drillOr = (el, cc_detail, entityId) => { if (!drill(el, cc_detail) && entityId) moreInfo(el, entityId); };

export const rows = sheet(`
:host { display: block; }
:host([hidden]) { display: none; }
.tile { padding-block: var(--ds-space-3); }
.tile__label { margin-bottom: var(--ds-space-1); }
button.row { width: 100%; box-sizing: border-box; min-height: var(--ds-touch); align-items: center; background: none; color: inherit; font: inherit;
  text-align: left; cursor: pointer; border: 0; border-top: 1px solid var(--divider-color); touch-action: manipulation; }
button.row:first-of-type { border-top: 0; }
button.row:focus-visible { outline: 2px solid var(--primary-color); outline-offset: -2px; border-radius: var(--ds-space-2); }
.row__v { text-align: right; overflow-wrap: anywhere; }
`);

export const rowButton = (name, text) => {
  const b = document.createElement("button");
  b.className = "row";
  b.innerHTML = `<span class="row__k"></span><span class="row__v"></span>`;
  b.firstChild.textContent = name;
  b.lastChild.textContent = text;
  b.setAttribute("aria-label", [name, text].filter(Boolean).join(" · "));
  return b;
};
