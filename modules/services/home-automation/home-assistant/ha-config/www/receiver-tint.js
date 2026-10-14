// Tints the Receiver mini-player with the colour the Living room player extracts from its cover art.

const SOURCE = "media_player.ma_home_theater";
const TARGET = "media_player.home_theater_2";

const players = (root, out = []) => {
  for (const el of root.querySelectorAll("*")) {
    if (el.tagName === "MINI-MEDIA-PLAYER") out.push(el);
    if (el.shadowRoot) players(el.shadowRoot, out);
  }
  return out;
};

let src;
let dst;

const sync = () => {
  if (!src || !dst || !src.isConnected || !dst.isConnected) {
    const all = players(document);
    src = all.find((p) => p.config && p.config.entity === SOURCE);
    dst = all.find((p) => p.config && p.config.entity === TARGET);
  }
  const bg = dst && dst.shadowRoot && dst.shadowRoot.querySelector(".mmp__bg");
  if (!bg) return;
  const grad = src && src.shadowRoot && src.shadowRoot.querySelector(".cover-gradient");
  const colour = grad && (grad.getAttribute("style") || "").match(/rgba?\([^)]*\)/);
  if (colour) bg.style.setProperty("background", colour[0], "important");
  else bg.style.removeProperty("background");
};

setInterval(sync, 1500);
