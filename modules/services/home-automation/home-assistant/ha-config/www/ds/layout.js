export const layoutMode = (w) => (w >= 1440 ? "wide" : w >= 820 ? "mid" : "narrow");
export const partition = (sections) => {
  const out = { rail: [], main: [], lead: [] };
  for (const s of sections) out[["rail", "lead"].includes(s.config?.cc_slot) ? s.config.cc_slot : "main"].push(s);
  return out;
};
export const columnCount = (w, max = 4) => Math.max(1, Math.min(max, Math.floor(w / 320)));
export const sectionSpan = (s, cols) => Math.min(s.config?.column_span ?? 1, cols);
export const detailConfig = (ev) => ev?.detail?.cc_detail ?? null;
export const pickSet = (sets = {}, key, fallback) => {
  if (Object.hasOwn(sets, key)) return { id: key, cards: sets[key] };
  const id = Object.keys(sets).filter((k) => key.startsWith(k)).sort((a, b) => b.length - a.length)[0];
  return id ? { id, cards: sets[id] } : { id: "default", cards: fallback ?? [] };
};
