export const layoutMode = (w) => (w >= 1440 ? "wide" : w >= 820 ? "mid" : "narrow");
export const partition = (sections) => {
  const out = { rail: [], main: [] };
  for (const s of sections) out[s.config?.cc_slot === "rail" ? "rail" : "main"].push(s);
  return out;
};
export const columnCount = (w, max = 4) => Math.max(1, Math.min(max, Math.floor(w / 320)));
export const sectionSpan = (s, cols) => Math.min(s.config?.column_span ?? 1, cols);
export const detailConfig = (ev) => ev?.detail?.cc_detail ?? null;
