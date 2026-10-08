// Maintenance cards: attention-list-card shows prioritised items as severity-tinted tiles with what to do, plus an optional collapsible list of broken references; battery-list-card shows device batteries grouped by room, lowest first, with a level bar and when each last reported.

const STYLE = `
  :host { display: block; }
  ha-card { padding: 4px 14px 10px; }
  .t { display: flex; align-items: center; gap: 12px; padding: 10px 0; border-top: 1px solid var(--divider-color); }
  .t:first-child { border-top: none; }
  .ic { width: 38px; height: 38px; border-radius: 50%; display: grid; place-items: center; flex: none; background: color-mix(in srgb, var(--c) 20%, transparent); color: var(--c); }
  .ic ha-icon { --mdc-icon-size: 21px; }
  .tx { flex: 1 1 auto; min-width: 0; }
  .ti { font-size: 14px; font-weight: 600; color: var(--primary-text-color); }
  .de { font-size: 12px; line-height: 1.35; color: var(--secondary-text-color); margin-top: 1px; }
  .ok { color: var(--success-color, #43a047); }
  button.tg { display: flex; align-items: center; gap: 4px; width: 100%; border: none; background: none; color: var(--secondary-text-color); font-size: 13px; font-weight: 600; padding: 0; min-height: 44px; cursor: pointer; border-top: 1px solid var(--divider-color); }
  button.tg ha-icon { --mdc-icon-size: 18px; }
  .rf { display: flex; justify-content: space-between; gap: 12px; padding: 5px 0; font-size: 12px; border-top: 1px solid var(--divider-color); }
  .rf:first-of-type { border-top: none; }
  .rf .id { color: var(--primary-text-color); word-break: break-all; }
  .rf .fl { color: var(--secondary-text-color); text-align: right; flex: none; max-width: 45%; }
  button.gb { display: flex; align-items: center; gap: 6px; width: 100%; min-height: 44px; border: none; background: none; padding: 0; cursor: pointer; color: var(--secondary-text-color); font: inherit; text-align: left; }
  button.gb ha-icon { --mdc-icon-size: 18px; flex: none; }
  .gl { font-size: 11px; font-weight: 700; letter-spacing: 0.6px; text-transform: uppercase; }
  .gs { margin-left: auto; font-size: 12px; font-variant-numeric: tabular-nums; }
  .r { display: flex; align-items: center; gap: 12px; padding: 7px 0; }
  .r .ic { width: 34px; height: 34px; }
  .r .ic ha-icon { --mdc-icon-size: 19px; }
  .n { overflow-wrap: anywhere; font-size: 14px; font-weight: 500; color: var(--primary-text-color); }
  .sb { font-size: 12px; color: var(--secondary-text-color); margin-top: 1px; }
  .sb .st { color: var(--warning-color, #ffa600); }
  .bar { flex: 0 1 72px; min-width: 24px; height: 6px; border-radius: 3px; background: var(--secondary-background-color); overflow: hidden; }
  .fill { height: 100%; border-radius: 3px; background: var(--c); }
  .lv { width: 44px; text-align: right; font-size: 14px; font-weight: 600; font-variant-numeric: tabular-nums; flex: none; }
  [data-e] { cursor: pointer; }
  .empty { padding: 14px 0; font-size: 13px; color: var(--secondary-text-color); }
`;

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const SEV = { error: "var(--error-color, #db4437)", warning: "var(--warning-color, #ffa600)", info: "var(--info-color, #039be5)" };
const levelColor = (n, lo, crit) => (n <= crit ? SEV.error : n < lo ? SEV.warning : "var(--success-color, #43a047)");

function ago(iso) {
  const t = Date.parse(iso);
  if (!isFinite(t)) return { text: "", stale: false, minutes: 0 };
  const m = Math.max(0, Math.round((Date.now() - t) / 60000));
  if (m < 1) return { text: "just now", stale: false, minutes: m };
  if (m < 60) return { text: `${m} min ago`, stale: false, minutes: m };
  const h = Math.round(m / 60);
  if (h < 48) return { text: `${h} h ago`, stale: false, minutes: m };
  const d = Math.round(h / 24);
  return { text: `${d} d ago`, stale: d >= 3, minutes: m };
}

class MaintenanceBase extends HTMLElement {
  setConfig(config) {
    if (!config || !config.entity) throw new Error(`${this.constructor.cardName}: entity is required`);
    this._config = config;
    this._open = {};
    this._html = "";
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      this.shadowRoot.addEventListener("click", (e) => {
        const t = e.target.closest("[data-e]");
        if (t) {
          this.dispatchEvent(new CustomEvent("hass-more-info", { bubbles: true, composed: true, detail: { entityId: t.dataset.e } }));
          return;
        }
        const b = e.target.closest("button.tg, button.gb");
        if (!b) return;
        this._open[b.dataset.k] = b.dataset.o !== "1";
        this._html = "";
        this._render();
      });
    }
  }

  getCardSize() {
    return 4;
  }

  set hass(hass) {
    this._hass = hass;
    if (this._config) this._render();
  }

  _paint(body) {
    const html = `<ha-card>${body}</ha-card>`;
    if (html === this._html) return;
    this._html = html;
    this.shadowRoot.innerHTML = `<style>${STYLE}</style>${html}`;
  }

  _isOpen(key, fallback) {
    return key in this._open ? this._open[key] : fallback;
  }

  _group(key, label, summary, open) {
    return `<button class="gb" data-k="${esc(key)}" data-o="${open ? 1 : 0}"><ha-icon icon="mdi:chevron-${open ? "up" : "down"}"></ha-icon><span class="gl">${esc(label)}</span><span class="gs">${summary}</span></button>`;
  }

  _toggle(key, label, count) {
    return `<button class="tg" data-k="${key}" data-o="${this._open[key] ? 1 : 0}"><ha-icon icon="mdi:chevron-${this._open[key] ? "up" : "down"}"></ha-icon>${esc(label)} (${count})</button>`;
  }
}

class AttentionListCard extends MaintenanceBase {
  _render() {
    const c = this._config;
    const s = this._hass.states[c.entity];
    if (!s || ["unavailable", "unknown"].includes(s.state)) {
      this._paint(`<div class="empty">Waiting for data…</div>`);
      return;
    }
    const items = s.attributes.items || [];
    let body = items.length
      ? items
          .map(
            (i) =>
              `<div class="t"${i.entity ? ` data-e="${esc(i.entity)}"` : ""} style="--c:${SEV[i.severity] || SEV.info}"><div class="ic"><ha-icon icon="${esc(i.icon || "mdi:alert-circle-outline")}"></ha-icon></div>` +
              `<div class="tx"><div class="ti">${esc(i.title)}</div><div class="de">${esc(i.detail || "")}</div></div></div>`,
          )
          .join("")
      : `<div class="t" style="--c:var(--success-color, #43a047)"><div class="ic"><ha-icon icon="mdi:check-circle-outline"></ha-icon></div><div class="tx"><div class="ti ok">All good</div><div class="de">No low batteries, offline devices, updates or broken references.</div></div></div>`;
    const d = c.details && this._hass.states[c.details.entity];
    const refs = (d && d.attributes.items) || [];
    if (refs.length) {
      body += this._toggle("refs", c.details.title || "Details", refs.length);
      if (this._open.refs) {
        body += refs.map((r) => `<div class="rf"><span class="id">${esc(r.id)}</span><span class="fl">${esc((r.files || []).join(", "))}</span></div>`).join("");
      }
    }
    this._paint(body);
  }
}

class BatteryListCard extends MaintenanceBase {
  _row(d, lo, crit) {
    const col = levelColor(d.level, lo, crit);
    const a = ago(d.reported);
    const parts = [];
    if (d.type) parts.push(esc(d.type));
    if (a.stale) parts.push(`<span class="st">no report for ${esc(a.text.replace(" ago", ""))}</span>`);
    return (
      `<div class="r" data-e="${esc(d.entity)}" style="--c:${col}"><div class="ic"><ha-icon icon="${esc(d.icon || "mdi:battery")}"></ha-icon></div>` +
      `<div class="tx"><div class="n">${esc(d.name)}</div><div class="sb">${parts.join(" · ")}</div></div>` +
      `<div class="bar"><div class="fill" style="width:${Math.max(2, Math.min(100, d.level))}%"></div></div>` +
      `<div class="lv" style="color:${col}">${Math.round(d.level)} %</div></div>`
    );
  }

  _render() {
    const s = this._hass.states[this._config.entity];
    if (!s || ["unavailable", "unknown"].includes(s.state)) {
      this._paint(`<div class="empty">Waiting for data…</div>`);
      return;
    }
    const lo = 25;
    const crit = 10;
    const live = (s.attributes.devices || []).filter((d) => d.level !== null && d.level !== undefined);
    const groups = {};
    live.forEach((d) => (groups[d.area || "Other"] = groups[d.area || "Other"] || []).push(d));
    Object.values(groups).forEach((g) => g.sort((a, b) => a.level - b.level));
    const order = Object.keys(groups).sort((a, b) => groups[a][0].level - groups[b][0].level || a.localeCompare(b));
    let body = order
      .map((k) => {
        const g = groups[k];
        const low = g[0].level;
        const open = this._isOpen(`g:${k}`, low < lo);
        const sum = `${g.length} ${g.length === 1 ? "device" : "devices"} · lowest <span style="color:${levelColor(low, lo, crit)}">${Math.round(low)} %</span>`;
        return this._group(`g:${k}`, k, sum, open) + (open ? g.map((d) => this._row(d, lo, crit)).join("") : "");
      })
      .join("");
    if (!order.length) body = `<div class="empty">No battery readings yet.</div>`;
    this._paint(body);
  }
}

class PersonalListCard extends MaintenanceBase {
  _render() {
    const s = this._hass.states[this._config.entity];
    if (!s || ["unavailable", "unknown"].includes(s.state)) {
      this._paint(`<div class="empty">Waiting for data…</div>`);
      return;
    }
    const lo = 20;
    const devices = (s.attributes.devices || []).filter((d) => d.level !== null && d.level !== undefined).sort((a, b) => a.level - b.level);
    if (!devices.length) {
      this._paint(`<div class="empty">No personal devices reporting.</div>`);
      return;
    }
    const body = devices
      .map((d) => {
        const col = d.charging ? "var(--success-color, #43a047)" : d.level < lo ? SEV.warning : "var(--success-color, #43a047)";
        const a = ago(d.reported);
        const parts = [d.charging ? "Charging" : d.power === "Not Charging" ? "On battery" : "Power unknown"];
        if (a.minutes >= 360) parts.push(`<span class="st">last seen ${esc(a.text)}</span>`);
        return (
          `<div class="r" data-e="${esc(d.entity)}" style="--c:${col}"><div class="ic"><ha-icon icon="${esc(d.charging ? "mdi:cellphone-charging" : d.icon || "mdi:cellphone")}"></ha-icon></div>` +
          `<div class="tx"><div class="n">${esc(d.name)}</div><div class="sb">${parts.join(" · ")}</div></div>` +
          `<div class="bar"><div class="fill" style="width:${Math.max(2, Math.min(100, d.level))}%"></div></div>` +
          `<div class="lv" style="color:${col}">${Math.round(d.level)} %</div></div>`
        );
      })
      .join("");
    this._paint(body);
  }
}

AttentionListCard.cardName = "attention-list-card";
BatteryListCard.cardName = "battery-list-card";
PersonalListCard.cardName = "personal-list-card";
customElements.define("attention-list-card", AttentionListCard);
customElements.define("battery-list-card", BatteryListCard);
customElements.define("personal-list-card", PersonalListCard);
