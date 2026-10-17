// Wrapping row of entity states: icon, label, value and an optional hint per entry; `colors` and `hints` map a state (or the value of the attribute named by `color_attribute`) to a theme tone (success, warning, error, info, inactive, primary) with `other` as the fallback; an entry is tappable only when it sets `tap: toggle`. `layout: rows` puts each entry on one line (label left, value right); `spark: {entity, title, hours}` adds an hourly-mean sparkline with its peak above the entries.

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
  .rows .row { grid-template-columns: 1fr; gap: 0; }
  .rows .it { align-items: center; }
  .rows .it > div { display: flex; flex: 1; align-items: baseline; justify-content: space-between; gap: 12px; min-width: 0; }
  .rows ha-icon { --mdc-icon-size: 18px; margin-top: 0; }
  .rows .lab { font-size: 13px; font-weight: 400; letter-spacing: 0; text-transform: none; }
  .rows .val { font-size: 13px; font-weight: 500; text-align: right; }
  .rows .hint { display: none; }
  .sp { padding: 8px 12px 6px; border-bottom: 1px solid var(--divider-color, rgba(127, 127, 127, 0.25)); margin-bottom: 2px; }
  .spt { display: flex; justify-content: space-between; flex-wrap: wrap; gap: 2px 12px; font-size: 12px; color: var(--secondary-text-color); margin-bottom: 6px; }
  .spt b { font-weight: 500; color: var(--primary-text-color); }
  .lgs { display: flex; flex-wrap: wrap; gap: 2px 12px; }
  .lg i { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-right: 4px; }
  .sp svg { display: block; width: 100%; height: 34px; overflow: visible; }
  ha-card.rows { padding: 2px 6px 4px; }
  .rows .it { padding: 4px 10px; }
  .chips { display: flex; flex-wrap: wrap; gap: 4px 14px; padding: 6px 10px; }
  .chips.head { padding: 8px 12px 0; }
  .chips .it { display: inline-flex; align-items: center; gap: 5px; padding: 0; }
  .chips .it > div { display: inline-flex; align-items: baseline; gap: 5px; min-width: 0; }
  .chips ha-icon { --mdc-icon-size: 16px; margin-top: 0; }
  .chips .lab { font-size: 11px; font-weight: 400; letter-spacing: 0; text-transform: none; }
  .chips .val { font-size: 13px; font-weight: 500; }
  .chips .hint { display: none; }
  .sp { cursor: pointer; }
  .hero { display: flex; align-items: baseline; gap: 4px; margin-bottom: 4px; }
  .hero b { font-size: 34px; font-weight: 500; line-height: 1; color: var(--primary-text-color); }
  .hero span { font-size: 14px; color: var(--secondary-text-color); }
  .sp .ar { fill: color-mix(in srgb, var(--info-color, #039be5) 15%, transparent); }
  .sp .ln { fill: none; stroke: var(--info-color, #039be5); stroke-width: 2; stroke-linejoin: round; vector-effect: non-scaling-stroke; }
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
        if (e.target.closest(".sp")) return this._moreInfo(this._series()[0].entity);
        const el = e.target.closest(".it.tap");
        const it = el && this._config.items[Number(el.dataset.i)];
        if (!it || !this._hass) return;
        if (it.tap === "more-info") return this._moreInfo(it.entity);
        if (it.confirm && !window.confirm(it.confirm)) return;
        this._hass.callService("homeassistant", "toggle", { entity_id: it.entity });
      });
    }
  }

  getCardSize() {
    return 2;
  }

  _moreInfo(entityId) {
    this.dispatchEvent(new CustomEvent("hass-more-info", { detail: { entityId }, bubbles: true, composed: true }));
  }

  set hass(hass) {
    this._hass = hass;
    this._loadSpark();
    this._render();
  }

  _series() {
    const sp = this._config.spark;
    return sp.series || [{ entity: sp.entity }];
  }

  _loadSpark() {
    const sp = this._config && this._config.spark;
    if (!sp || this._sparkBusy || (this._spark && Date.now() - this._spark.at < 900000)) return;
    this._sparkBusy = true;
    const end = new Date();
    const ids = this._series().map((s) => s.entity);
    this._hass
      .callWS({ type: "recorder/statistics_during_period", start_time: new Date(end - (sp.hours || 24) * 3600000).toISOString(), end_time: end.toISOString(), statistic_ids: ids, period: "hour", types: ["mean"] })
      .then((r) => (this._spark = { at: Date.now(), pts: ids.map((id) => (r[id] || []).map((x) => x.mean).filter((v) => v != null)) }))
      .catch(() => (this._spark = { at: Date.now(), pts: [] }))
      .finally(() => {
        this._sparkBusy = false;
        this._render();
      });
  }

  _sparkHtml() {
    const sp = this._config.spark;
    const all = this._spark ? this._spark.pts : [];
    if (!sp || !all.some((p) => p.length > 1)) return "";
    const series = this._series();
    const scale = Math.max(...all.flat()) || 1;
    const k = sp.scale ?? 1;
    const fmt = (v, unit) => {
      const x = v * k;
      return `${x < 1 && k !== 1 ? x.toFixed(2) : x.toFixed(sp.decimals ?? 0)} ${esc(sp.unit ?? unit)}`;
    };
    const unitOf = (id) => (this._hass.states[id] && this._hass.states[id].attributes.unit_of_measurement) || "";
    const lines = series
      .map((s, i) => {
        const pts = all[i] || [];
        if (pts.length < 2) return "";
        const line = pts.map((v, j) => `${((j / (pts.length - 1)) * 100).toFixed(1)},${(29 - (v / scale) * 27).toFixed(1)}`).join(" ");
        return `${i ? "" : `<polygon class="ar" points="0,30 ${line} 100,30"/>`}<polyline class="ln" style="stroke:${esc(s.color || (i ? "var(--accent-color, #c9a7e8)" : "var(--info-color, #039be5)"))}" points="${line}"/>`;
      })
      .join("");
    const legend = series
      .map((s, i) => `<span class="lg">${series.length > 1 ? `<i style="background:${esc(s.color || (i ? "var(--accent-color, #c9a7e8)" : "var(--info-color, #039be5)"))}"></i>${esc(s.name || "")} ` : ""}peak <b>${all[i] && all[i].length ? fmt(Math.max(...all[i]), unitOf(s.entity)) : "-"}</b></span>`)
      .join("");
    const e = this._hass.states[series[0].entity];
    const nowV = e ? parseFloat(e.state) : NaN;
    const hero = sp.hero && isFinite(nowV) ? `<div class="hero"><b>${nowV.toFixed(sp.decimals ?? 0)}</b><span>${esc(unitOf(series[0].entity))}</span></div>` : "";
    return `<div class="sp">${hero}<div class="spt"><span>${esc(sp.title || "")}</span><span class="lgs">${legend}</span></div><svg viewBox="0 0 100 30" preserveAspectRatio="none">${lines}</svg></div>`;
  }

  _cell(it, i) {
    const c = this._config;
    const s = this._hass.states[it.entity];
    if (it.hide_when && s && it.hide_when.includes(s.state)) return "";
    const dead = !s || s.state === "unavailable" || s.state === "unknown";
    const text = dead ? "Unavailable" : (it.labels && it.labels[s.state]) || s.state.charAt(0).toUpperCase() + s.state.slice(1);
    const unit = !dead && it.unit && s.attributes.unit_of_measurement;
    const shown = unit ? `${text} ${unit}` : text;
    const key = dead ? "" : it.color_attribute ? s.attributes[it.color_attribute] : s.state;
    const hint = dead ? "" : (it.hints && it.hints[key]) || it.hint || "";
    const base = it.color || c.color || "primary";
    const color = tone(dead ? "inactive" : (it.colors && (it.colors[key] || it.colors.other)) || (s.state === "off" ? "inactive" : base));
    const tap = (it.tap === "toggle" || it.tap === "more-info") && !dead;
    return (
      `<div class="it${dead || s.state === "off" ? " off" : ""}${tap ? " tap" : ""}" data-i="${i}" style="--c:${esc(color)}">${it.icon ? `<ha-icon icon="${esc(it.icon)}"></ha-icon>` : ""}` +
      `<div><div class="lab">${esc(it.name ?? ((s && s.attributes.friendly_name) || ""))}</div><div class="val">${esc(shown)}</div>${hint ? `<div class="hint">${esc(hint)}</div>` : ""}</div></div>`
    );
  }

  _render() {
    if (!this._config || !this._hass) return;
    const c = this._config;
    const head = (c.head || []).map((it) => this._cell(it, -1)).join("");
    const cells = c.items.map((it, i) => this._cell(it, i)).join("");
    const spark = this._sparkHtml();
    this.style.display = head || cells || spark ? "" : "none";
    const chips = c.layout === "chips" ? " chips" : "";
    this.shadowRoot.innerHTML =
      `<style>${STYLE}</style><ha-card class="${c.layout === "rows" ? "rows" : ""}">${head ? `<div class="row chips head">${head}</div>` : ""}${spark}` +
      `${cells ? `<div class="row${chips}" style="--min:${esc(c.min_width || "170px")}">${cells}</div>` : ""}</ha-card>`;
  }
}

customElements.define("status-row-card", StatusRowCard);
