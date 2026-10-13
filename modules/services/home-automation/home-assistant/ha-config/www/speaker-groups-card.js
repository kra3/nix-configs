// Create, edit and dissolve speaker groups: pick free speakers, tap Group; member chips remove, Ungroup dissolves.

const STYLE = `
:host { display: block; min-width: 0; }
ha-card { min-width: 0; overflow: hidden; padding: 6px 10px 10px; display: flex; flex-direction: column; gap: 8px; }
.head { display: flex; align-items: center; gap: 8px; min-height: 40px; font-size: 14px; font-weight: 500; }
.head ha-icon { color: var(--secondary-text-color); }
.head .t { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.row { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; }
.chip { display: inline-flex; align-items: center; gap: 6px; min-height: 36px; padding: 0 12px; border: 0; border-radius: 18px; cursor: pointer; font: inherit; font-size: 13px;
  color: var(--primary-text-color); background: color-mix(in srgb, var(--secondary-text-color) 12%, transparent); }
.chip:hover { background: color-mix(in srgb, var(--secondary-text-color) 20%, transparent); }
.chip.on { color: var(--text-primary-color, #fff); background: var(--primary-color); }
.chip.go { color: var(--primary-color); background: color-mix(in srgb, var(--primary-color) 16%, transparent); }
.chip[disabled] { opacity: 0.4; cursor: default; }
.chip.lead { cursor: default; background: color-mix(in srgb, var(--primary-color) 16%, transparent); color: var(--primary-text-color); }
.group { display: flex; flex-direction: column; gap: 6px; padding: 8px; border-radius: 12px; background: color-mix(in srgb, var(--secondary-text-color) 8%, transparent); }
.hint { font-size: 12px; color: var(--secondary-text-color); padding: 0 6px; }
ha-icon { --mdc-icon-size: 18px; flex: none; }
`;

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const ic = (n) => `<ha-icon icon="mdi:${n}"></ha-icon>`;

class SpeakerGroupsCard extends HTMLElement {
  setConfig(config) {
    if (!config || !Array.isArray(config.speakers) || config.speakers.length < 2) {
      throw new Error("speaker-groups-card: at least two speakers are required");
    }
    this._config = config;
    this._sel = new Set();
    this._sig = "";
    if (!this.shadowRoot) {
      this.attachShadow({ mode: "open" });
      this.shadowRoot.addEventListener("click", (e) => this._click(e));
    }
  }

  getCardSize() { return 3; }

  getGridOptions() { return { columns: 12, min_columns: 6 }; }

  set hass(hass) {
    this._hass = hass;
    if (this._config) this._render();
  }

  _name(id) { return (this._config.speakers.find((s) => s.entity === id) || {}).name || id; }

  _groups() {
    const ids = this._config.speakers.map((s) => s.entity);
    const groups = [];
    for (const id of ids) {
      const st = this._hass.states[id];
      const m = ((st && st.attributes.group_members) || []).filter((x) => ids.includes(x));
      if (m.length > 1 && m[0] === id) groups.push(m);
    }
    return groups;
  }

  _click(e) {
    const b = e.target.closest("[data-a]");
    if (!b || b.disabled) return;
    const a = b.dataset.a;
    const id = b.dataset.e;
    const call = (service, data) => this._hass.callService("media_player", service, data);
    if (a === "pick") {
      if (this._sel.has(id)) this._sel.delete(id); else this._sel.add(id);
      this._sig = "";
      this._render();
    } else if (a === "group") {
      const [lead, ...rest] = [...this._sel];
      this._sel.clear();
      call("join", { entity_id: lead, group_members: rest });
    } else if (a === "remove") call("unjoin", { entity_id: id });
    else if (a === "ungroup") b.dataset.m.split(",").forEach((m) => call("unjoin", { entity_id: m }));
  }

  _render() {
    const groups = this._groups();
    const grouped = new Set(groups.flat());
    const free = this._config.speakers.filter((s) => !grouped.has(s.entity));
    for (const id of [...this._sel]) if (grouped.has(id)) this._sel.delete(id);
    const sig = JSON.stringify([groups, [...this._sel]]);
    if (sig === this._sig) return;
    this._sig = sig;

    const groupHtml = groups.map((m) => `<div class="group">
        <div class="row">${ic("speaker-multiple")}<b>${esc(this._name(m[0]))}</b> leads
          <span style="flex:1"></span><button class="chip" data-a="ungroup" data-m="${m.join(",")}">${ic("link-off")}Ungroup</button></div>
        <div class="row">${m.map((x, i) => i === 0 ? `<span class="chip lead">${esc(this._name(x))}</span>` : `<button class="chip" data-a="remove" data-e="${x}" title="Remove from group">${esc(this._name(x))}${ic("close")}</button>`).join("")}</div>
      </div>`).join("");
    const canGroup = this._sel.size >= 2;
    const newHtml = free.length >= 2 ? `<div class="row">${free.map((s) => `<button class="chip ${this._sel.has(s.entity) ? "on" : ""}" data-a="pick" data-e="${s.entity}">${ic(s.icon ? s.icon.replace("mdi:", "") : "speaker")}${esc(s.name)}</button>`).join("")}
        <button class="chip go" data-a="group" ${canGroup ? "" : "disabled"}>${ic("link-variant")}Group</button></div>
        <div class="hint">${canGroup ? `${esc(this._name([...this._sel][0]))} will lead.` : "Tap two or more speakers to group them."}</div>` : "";
    this.shadowRoot.innerHTML = `<style>${STYLE}</style><ha-card>
      <div class="head">${ic("speaker-multiple")}<span class="t">Groups</span></div>
      ${groupHtml}${newHtml}
      ${!groups.length && free.length < 2 ? `<div class="hint">No free speakers to group.</div>` : ""}
    </ha-card>`;
  }
}

if (typeof customElements !== "undefined" && !customElements.get("speaker-groups-card")) {
  customElements.define("speaker-groups-card", SpeakerGroupsCard);
  window.customCards = window.customCards || [];
  window.customCards.push({ type: "speaker-groups-card", name: "Speaker groups card", description: "Create, edit and dissolve speaker groups." });
}
