#!/usr/bin/env python3
import argparse
import gzip
import os
import re
import tempfile
import urllib.request
import xml.etree.ElementTree as ET

URL = "https://iptv-epg.org/files/epg-in.xml.gz"
MIN_CHANNELS = 10
# our tvg-id base -> id in the upstream guide, where the two differ beyond case
ALIASES = {"NDTVProfit.in": "NDTVProfitPrime.in", "BloombergTV.us": "BloombergTelevision.in"}


def wanted(allow):
    out = set()
    for line in open(allow):
        if line.strip() and not line.startswith("#"):
            for i in (line.rstrip("\n").split("\t") + [""] * 4)[3].split(","):
                if i and not i.startswith("yt:"):
                    out.add(i.split("@")[0])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--allow", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    ours = {ALIASES.get(i, i).lower(): i for i in wanted(a.allow)}
    req = urllib.request.Request(URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        root = ET.fromstring(gzip.decompress(r.read()))

    keep = {}
    for ch in root.findall("channel"):
        mine = ours.get(ch.get("id").lower())
        if mine and mine not in keep.values():
            keep[ch.get("id")] = mine
    if len(keep) < MIN_CHANNELS:
        raise SystemExit(f"only {len(keep)} channels matched; leaving output untouched")

    for el in list(root):
        up = el.get("id" if el.tag == "channel" else "channel")
        if el.tag not in ("channel", "programme") or up not in keep:
            root.remove(el)
        else:
            el.set("id" if el.tag == "channel" else "channel", keep[up])

    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(a.out)))
    os.close(fd)
    ET.ElementTree(root).write(tmp, encoding="utf-8", xml_declaration=True)
    os.chmod(tmp, 0o644)
    os.replace(tmp, a.out)
    print(f"{len(keep)} channels, {len(root.findall('programme'))} programmes")


if __name__ == "__main__":
    main()
