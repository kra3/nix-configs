"""Normalize artist/albumartist credits on every write.

Collapses dotted/spaced initials to a bare-letters form ("S. P." / "S.P." ->
"SP"), and unifies the multi-credit separator to ", " (so "&", "/", ";" all
become the same style) -- the same rules applied library-wide in the
Hindi/Malayalam/Tamil/Telugu/Mixed-International/Devotional cleanup pass.
"""

import re

from beets.plugins import BeetsPlugin

INITIALS_RE = re.compile(r"(?:^|(?<=\s))((?:[A-Z]\.\s*)+)")
SPLIT_RE = re.compile(r"\s*[&,/;]\s*")
CANON_SEP = ", "

# Duo/trio act names written as bare first names joined by "&" are the act's
# own name, not multiple separate credits -- protect them before splitting.
DUO_ACTS = {
    "Vishal & Shekhar": "Vishal-Shekhar",
    "Jatin & Lalit": "Jatin-Lalit",
    "Sajid & Wajid": "Sajid-Wajid",
    "Salim & Sulaiman": "Salim-Sulaiman",
    "Shankar & Ehsaan & Loy": "Shankar–Ehsaan–Loy",
    "Kalyanji & Anandji": "Kalyanji-Anandji",
}
DUO_RE = re.compile("|".join(re.escape(k) for k in DUO_ACTS))


def _replace_initials(m, full):
    prefix = m.group(1)
    letters = re.sub(r"[.\s]", "", prefix)
    rest = full[m.end() :]
    if not rest:
        return letters
    # A real surname/word starts with an uppercase letter followed by lowercase
    # (e.g. "Savithri"): always separate with a space. Otherwise `rest` starts
    # with another bare initial-like uppercase letter -- glue with no space.
    is_word = rest[0].isupper() and len(rest) > 1 and rest[1].islower()
    is_word = is_word or not rest[0].isupper()
    return letters + (" " if is_word else "")


def normalize_segment(seg):
    out = []
    pos = 0
    for m in INITIALS_RE.finditer(seg):
        out.append(seg[pos : m.start()])
        out.append(_replace_initials(m, seg))
        pos = m.end()
    out.append(seg[pos:])
    return "".join(out)


def normalize_name(name):
    if not name:
        return name
    name = DUO_RE.sub(lambda m: DUO_ACTS[m.group(0)], name)
    segments = SPLIT_RE.split(name)
    return CANON_SEP.join(normalize_segment(s) for s in segments)


class NormalizeNamesPlugin(BeetsPlugin):
    def __init__(self):
        super().__init__()
        self.register_listener("write", self.on_write)

    def on_write(self, item, path, tags):
        for field in ("artist", "albumartist"):
            value = tags.get(field)
            if value:
                tags[field] = normalize_name(value)
