// Compact scene control per room: Auto, plus a Mood button that opens a picker of every Scene Presets preset; state lives in an input_text ("Auto" or a preset id).

const PRESET_URL = "/assets/scene_presets/scene_presets.json";
const imgUrl = (p) => `/assets/scene_presets/${p.img}`;

let presetPromise;
const loadPresets = () => {
  if (!presetPromise) {
    presetPromise = fetch(PRESET_URL)
      .then((r) => {
        if (!r.ok) throw new Error(r.status);
        return r.json();
      })
      .catch((e) => {
        presetPromise = undefined;
        throw e;
      });
  }
  return presetPromise;
};

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

const STYLE = `
  :host { display: block; }
  ha-card { padding: 10px 12px 12px; }
  .rooms { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 8px; }
  .rm { position: relative; font: inherit; font-size: 13px; font-weight: 600; padding: 6px 12px; min-height: 32px; border-radius: 16px; border: 1px solid var(--divider-color); background: none; color: var(--secondary-text-color); cursor: pointer; }
  .rm.sel { background: var(--primary-color); border-color: var(--primary-color); color: var(--text-primary-color, #fff); }
  .rm.act::after { content: ""; position: absolute; top: 2px; right: 3px; width: 7px; height: 7px; border-radius: 50%; background: var(--warning-color, orange); }
  .bs { display: grid; grid-template-columns: 1fr 2fr; gap: 8px; }
  .b { position: relative; font: inherit; height: 56px; border-radius: 12px; overflow: hidden; cursor: pointer; border: 2px solid transparent; background: var(--secondary-background-color) center / cover; display: flex; align-items: center; gap: 8px; padding: 0 12px; color: var(--primary-text-color); text-align: left; }
  .b.on { border-color: var(--primary-color); box-shadow: 0 0 0 1px var(--primary-color); }
  .b.img::before { content: ""; position: absolute; inset: 0; background: linear-gradient(to top, rgba(0,0,0,0.6), rgba(0,0,0,0.1)); }
  .b.img { color: #fff; }
  .lb { position: relative; font-size: 14px; font-weight: 600; line-height: 1.15; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  ha-icon { position: relative; --mdc-icon-size: 22px; flex: none; }
  .cap { margin-top: 8px; font-size: 12px; color: var(--secondary-text-color); }
  .th { margin-top: 10px; padding-top: 8px; border-top: 1px solid var(--divider-color); font-size: 11px; font-weight: 700; letter-spacing: 0.6px; text-transform: uppercase; color: var(--secondary-text-color); }
  .tg { font: inherit; width: 100%; min-height: 48px; display: flex; align-items: center; gap: 12px; padding: 6px 4px; border: 0; border-radius: 10px; background: none; color: var(--primary-text-color); cursor: pointer; text-align: left; }
  .tg:hover { background: var(--secondary-background-color); }
  .tg ha-icon { color: var(--state-inactive-color, var(--secondary-text-color)); }
  .tg.on ha-icon { color: var(--primary-color); }
  .tx { flex: 1; min-width: 0; display: flex; flex-direction: column; }
  .tn { font-size: 14px; font-weight: 600; }
  .td { font-size: 12px; line-height: 1.3; color: var(--secondary-text-color); }
  .tv { font-size: 13px; font-weight: 600; color: var(--state-inactive-color, var(--secondary-text-color)); }
  .tg.on .tv { color: var(--primary-color); }
`;

const PICKER_STYLE = `
  :host { all: initial; }
  .ov { position: fixed; inset: 0; z-index: 10000; background: rgba(0,0,0,0.6); display: flex; align-items: center; justify-content: center; font-family: var(--paper-font-body1_-_font-family, Roboto, sans-serif); }
  .dg { display: flex; flex-direction: column; background: var(--card-background-color, #1c1c1c); color: var(--primary-text-color, #eee); width: min(960px, 100%); max-height: 90vh; height: 760px; border-radius: 16px; overflow: hidden; }
  .hd { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 14px 16px 8px; }
  .ti { font-size: 18px; font-weight: 600; }
  .x { font: inherit; font-size: 22px; line-height: 1; width: 44px; height: 44px; border: 0; border-radius: 50%; background: none; color: inherit; cursor: pointer; }
  .q { margin: 0 16px 8px; font: inherit; font-size: 15px; padding: 10px 14px; min-height: 44px; box-sizing: border-box; border-radius: 22px; border: 1px solid var(--divider-color, #444); background: var(--secondary-background-color, #2a2a2a); color: inherit; }
  .cs { display: flex; gap: 6px; padding: 0 16px 10px; overflow-x: auto; flex: none; scrollbar-width: none; }
  .c { flex: none; font: inherit; font-size: 13px; font-weight: 600; padding: 6px 12px; min-height: 32px; border-radius: 16px; border: 1px solid var(--divider-color, #444); background: none; color: var(--secondary-text-color, #999); cursor: pointer; white-space: nowrap; }
  .c.sel { background: var(--primary-color, #03a9f4); border-color: var(--primary-color, #03a9f4); color: var(--text-primary-color, #fff); }
  .g { flex: 1; overflow-y: auto; padding: 4px 16px 16px; display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 10px; align-content: start; }
  .t { position: relative; font: inherit; height: 84px; border-radius: 12px; overflow: hidden; cursor: pointer; border: 2px solid transparent; background: var(--secondary-background-color, #2a2a2a); padding: 0; display: flex; align-items: flex-end; text-align: left; }
  .t img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }
  .t::after { content: ""; position: absolute; inset: 0; background: linear-gradient(to top, rgba(0,0,0,0.65), rgba(0,0,0,0.05)); }
  .t span { position: relative; z-index: 1; font-size: 13px; font-weight: 600; color: #fff; padding: 6px 8px; line-height: 1.1; }
  .t.on { border-color: var(--primary-color, #03a9f4); }
  .em { grid-column: 1 / -1; padding: 24px; text-align: center; color: var(--secondary-text-color, #999); }
  @media (max-width: 600px) {
    .ov { align-items: stretch; }
    .dg { width: 100%; max-height: none; height: 100%; border-radius: 0; padding-top: env(safe-area-inset-top, 0px); padding-bottom: env(safe-area-inset-bottom, 0px); box-sizing: border-box; }
  }
`;

class ScenePickerCard extends HTMLElement {
  setConfig(config) {
    if (!config || !(config.rooms || config.entity)) throw new Error("scene-picker-card: rooms (or entity) are required");
    this._config = config;
    this._rooms = config.rooms || [{ name: config.name, entity: config.entity }];
    this._pending = {};
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      this.shadowRoot.addEventListener("click", (e) => {
        const r = e.target.closest(".rm");
        if (r) {
          this._sel = Number(r.dataset.room);
          this._render();
          return;
        }
        const g = e.target.closest(".tg");
        if (g && this._hass) {
          this._hass.callService("homeassistant", "toggle", { entity_id: this._config.toggles[Number(g.dataset.t)].entity });
          return;
        }
        const b = e.target.closest(".b");
        if (!b || !this._hass) return;
        if (b.classList.contains("auto")) this._set(this._room().entity, "Auto");
        else this._openPicker();
      });
    }
  }

  getCardSize() {
    return 2;
  }

  set hass(hass) {
    this._hass = hass;
    for (const r of this._rooms) {
      const s = hass.states[r.entity];
      if (this._pending[r.entity] && s && s.state === this._pending[r.entity]) delete this._pending[r.entity];
    }
    if (this._sel === undefined) {
      const i = this._rooms.findIndex((r) => this._value(r.entity) !== "Auto");
      this._sel = i < 0 ? 0 : i;
    }
    if (!this._loading) {
      this._loading = true;
      loadPresets()
        .then((d) => {
          this._byId = new Map(d.presets.map((p) => [p.id, p]));
          this._render();
        })
        .catch(() => {
          this._loading = false;
        });
    }
    this._render();
  }

  _room() {
    return this._rooms[this._sel || 0];
  }

  _value(entity) {
    const s = this._hass.states[entity];
    return this._pending[entity] || (s ? s.state : "");
  }

  _set(entity, value) {
    this._pending[entity] = value;
    this._render();
    this._hass.callService("input_text", "set_value", { entity_id: entity, value });
  }

  _togglesHtml() {
    const t = this._config.toggles;
    if (!t || !t.length) return "";
    const rows = t
      .map((x, i) => {
        const s = this._hass.states[x.entity];
        const dead = !s || s.state === "unavailable" || s.state === "unknown";
        const on = !dead && s.state === "on";
        const hint = dead ? "" : (x.hints && x.hints[s.state]) || "";
        return `<button class="tg${on ? " on" : ""}" data-t="${i}"><ha-icon icon="${esc(x.icon || "")}"></ha-icon><span class="tx"><span class="tn">${esc(x.name)}</span><span class="td">${esc(hint)}</span></span><span class="tv">${dead ? "Unavailable" : on ? "On" : "Off"}</span></button>`;
      })
      .join("");
    return `${this._config.toggles_label ? `<div class="th">${esc(this._config.toggles_label)}</div>` : ""}${rows}`;
  }

  _render() {
    if (!this._hass) return;
    const room = this._room();
    const s = this._hass.states[room.entity];
    const v = this._value(room.entity);
    const dead = !s || s.state === "unavailable" || s.state === "unknown";
    const auto = v === "Auto";
    const p = this._byId && this._byId.get(v);
    const moodLabel = auto || dead ? "Pick a mood" : p ? p.name : "Custom mood";
    const cap = dead ? "Unavailable" : auto ? "Auto · Adaptive Lighting" : `${p ? p.name : "Custom mood"} · until the room is empty`;
    const picker =
      this._rooms.length > 1
        ? `<div class="rooms">${this._rooms.map((r, i) => `<button class="rm${i === this._sel ? " sel" : ""}${this._value(r.entity) !== "Auto" ? " act" : ""}" data-room="${i}">${esc(r.name)}</button>`).join("")}</div>`
        : "";
    this.shadowRoot.innerHTML =
      `<style>${STYLE}</style><ha-card>${picker}<div class="bs">` +
      `<button class="b auto${auto ? " on" : ""}"><ha-icon icon="mdi:theme-light-dark"></ha-icon><span class="lb">Auto</span></button>` +
      `<button class="b mood${!auto && !dead ? " on" : ""}${p && !auto ? " img" : ""}"${p && !auto ? ` style="background-image:url('${esc(imgUrl(p))}')"` : ""}><ha-icon icon="mdi:palette"></ha-icon><span class="lb">${esc(moodLabel)}</span></button>` +
      `</div><div class="cap">${esc(cap)}</div>${this._togglesHtml()}</ha-card>`;
  }

  _openPicker() {
    const room = this._room();
    const host = document.createElement("div");
    host.attachShadow({ mode: "open" });
    document.body.appendChild(host);
    const root = host.shadowRoot;
    let cat = "all";
    let q = "";
    let data = null;
    const close = () => {
      document.removeEventListener("keydown", onKey);
      host.remove();
    };
    const onKey = (e) => {
      if (e.key === "Escape") close();
    };
    document.addEventListener("keydown", onKey);
    root.innerHTML =
      `<style>${PICKER_STYLE}</style><div class="ov"><div class="dg"><div class="hd"><div class="ti">Mood · ${esc(room.name || "")}</div><button class="x" aria-label="Close">×</button></div>` +
      `<input class="q" type="search" placeholder="Search moods" aria-label="Search moods"><div class="cs"></div><div class="g"><div class="em">Loading moods…</div></div></div></div>`;
    const chips = root.querySelector(".cs");
    const grid = root.querySelector(".g");
    const draw = () => {
      if (!data) return;
      const cur = this._value(room.entity);
      chips.innerHTML = [{ id: "all", name: "All" }, ...data.categories].map((c) => `<button class="c${c.id === cat ? " sel" : ""}" data-cat="${esc(c.id)}">${esc(c.name)}</button>`).join("");
      const needle = q.trim().toLowerCase();
      const list = data.presets.filter((p) => (cat === "all" || p.categoryId === cat) && (!needle || p.name.toLowerCase().includes(needle)));
      grid.innerHTML = list.length
        ? list.map((p) => `<button class="t${p.id === cur ? " on" : ""}" data-id="${esc(p.id)}"><img loading="lazy" decoding="async" alt="" src="${esc(imgUrl(p))}"><span>${esc(p.name)}</span></button>`).join("")
        : '<div class="em">No moods match</div>';
    };
    loadPresets()
      .then((d) => {
        data = d;
        draw();
      })
      .catch(() => {
        grid.innerHTML = '<div class="em">Moods are unavailable</div>';
      });
    root.addEventListener("click", (e) => {
      if (e.target.classList.contains("ov") || e.target.closest(".x")) return close();
      const c = e.target.closest(".c");
      if (c) {
        cat = c.dataset.cat;
        return draw();
      }
      const t = e.target.closest(".t");
      if (t) {
        this._set(room.entity, t.dataset.id);
        close();
      }
    });
    root.querySelector(".q").addEventListener("input", (e) => {
      q = e.target.value;
      draw();
    });
    root.querySelector(".q").focus();
  }
}

customElements.define("scene-picker-card", ScenePickerCard);
