"""Keep MP3 tags to the standard set after every write.

Deletes every ID3 frame that is not on the keep list (Picard "Classical Extras"
config/error tags, duplicate multi-value artist fields, ...), so current and
future imports end up with the same uniform tag set.
"""

import os

from beets.plugins import BeetsPlugin
from mutagen.id3 import ID3, ID3NoHeaderError

KEEP_FRAMES = {
    "TIT2",  # title
    "TPE1",  # artist
    "TALB",  # album
    "TPE2",  # album artist
    "TRCK",  # track
    "TPOS",  # disc
    "TDRC", "TYER", "TDAT", "TDOR", "TORY",  # dates
    "TCON",  # genre
    "TCOM",  # composer
    "TIT1",  # grouping
    "TCMP",  # compilation
    "TLAN",  # language
    "TPUB",  # publisher
    "TSRC",  # ISRC
    "TSOP", "TSO2", "TSOA", "TSOT",  # sort names
    "TCOP",  # copyright
    "TEXT", "TOLY",  # lyricist
    "TBPM", "TKEY", "TLEN", "TMED",
    "APIC",  # cover art
    "USLT", "SYLT",  # lyrics
    "COMM",
    "POPM", "PCNT",
    "UFID",  # MusicBrainz recording id
}

KEEP_TXXX = {
    "catalognumber", "barcode", "asin", "label", "originalyear", "instrument",
    "albumartistsort",
}

KEEP_TXXX_PREFIXES = ("musicbrainz ", "acoustid ", "replaygain_", "ab:")


def is_junk(key: str, frame) -> bool:
    frame_id = key.split(":", 1)[0]
    if frame_id != "TXXX":
        return frame_id not in KEEP_FRAMES
    desc = getattr(frame, "desc", "").lower()
    return desc not in KEEP_TXXX and not desc.startswith(KEEP_TXXX_PREFIXES)


def strip_file(path: str) -> int:
    """Remove junk frames from one MP3 and return how many were removed."""
    try:
        tags = ID3(path)
    except ID3NoHeaderError:
        return 0
    junk = [key for key, frame in tags.items() if is_junk(key, frame)]
    for key in junk:
        del tags[key]
    if junk:
        tags.save(path)
    return len(junk)


class StripJunkTagsPlugin(BeetsPlugin):
    def __init__(self):
        super().__init__()
        self.register_listener("after_write", self.on_after_write)

    def on_after_write(self, item, path):
        path = os.fsdecode(path)
        if not path.lower().endswith(".mp3"):
            return
        removed = strip_file(path)
        if removed:
            self._log.debug("removed {} junk frame(s) from {}", removed, path)
