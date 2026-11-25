#!/usr/bin/env python3
"""Mirror ranjithkb.com's Akashvani (AIR) Malayalam stations into Navidrome and Music Assistant."""
import argparse
import hashlib
import json
import os
import re
import secrets
import urllib.parse
import urllib.request

LIST_URL = "https://ranjithkb.com/js/stations/malayalam.js"
MIN_STATIONS = 5


def http(url, data=None, headers=None):
    req = urllib.request.Request(url, data=data, headers={"User-Agent": "Mozilla/5.0", **(headers or {})})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def air_stations():
    src = http(LIST_URL).decode()
    # the file is `window.STATIONS = [ ... ];` with JSON-compatible array contents
    stations = json.loads(re.search(r"window\.STATIONS\s*=\s*(\[.*\])\s*;?\s*$", src, re.S | re.M).group(1))
    out = {}
    for s in stations:
        if s.get("category") != "air" or s.get("tv") or s.get("offline") or s.get("hidden"):
            continue
        urls = [u for u in s.get("streams", []) if u not in s.get("exclude", [])]
        if urls:
            out[s["name"]] = urls[0]
    if len(out) < MIN_STATIONS:
        raise SystemExit(f"only {len(out)} AIR stations parsed; leaving apps untouched")
    return out


class Navidrome:
    def __init__(self, base, user, password):
        self.base, self.user, self.password = base, user, password

    def call(self, ep, **params):
        salt = secrets.token_hex(6)
        q = {
            "u": self.user,
            "t": hashlib.md5((self.password + salt).encode()).hexdigest(),
            "s": salt,
            "v": "1.16.1",
            "c": "radio-sync",
            "f": "json",
            **params,
        }
        r = json.loads(http(f"{self.base}/rest/{ep}?{urllib.parse.urlencode(q)}"))["subsonic-response"]
        if r["status"] != "ok":
            raise SystemExit(f"navidrome {ep}: {r.get('error')}")
        return r

    def sync(self, want, dry):
        have = {
            s["name"]: s for s in self.call("getInternetRadioStations").get("internetRadioStations", {}).get("internetRadioStation", [])
        }
        for name, url in want.items():
            cur = have.get(name)
            if cur and cur["streamUrl"] == url:
                continue
            print(f"navidrome: {'update' if cur else 'add'} {name} -> {url}")
            if dry:
                continue
            if cur:
                self.call("updateInternetRadioStation", id=cur["id"], streamUrl=url, name=name)
            else:
                self.call("createInternetRadioStation", streamUrl=url, name=name)


class MusicAssistant:
    def __init__(self, base, token):
        self.base, self.token = base, token

    def call(self, command, **args):
        body = json.dumps({"command": command, "args": args}).encode()
        out = http(
            f"{self.base}/api",
            body,
            {"Authorization": f"Bearer {self.token}", "Content-Type": "application/json"},
        )
        return json.loads(out) if out else None

    def sync(self, want, dry):
        items = self.call("music/radios/library_items", provider="builtin", limit=1000) or []
        have = {i["name"] for i in items}
        # add-only: replacing a changed URL would drop the station's favourites and history
        for name, url in want.items():
            if name in have:
                continue
            print(f"music-assistant: add {name} -> {url}")
            if not dry:
                self.call("builtin/add_radio", url=url, name=name)


def cred(name):
    return open(os.path.join(os.environ["CREDENTIALS_DIRECTORY"], name)).read().strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--navidrome", required=True)
    ap.add_argument("--navidrome-user", default="radio-sync")
    ap.add_argument("--ma", required=True)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    want = air_stations()
    print(f"{len(want)} AIR stations upstream")
    if a.dry_run and "CREDENTIALS_DIRECTORY" not in os.environ:
        for n, u in want.items():
            print(f"  {n} -> {u}")
        return
    failed = []
    for target in (
        lambda: Navidrome(a.navidrome, a.navidrome_user, cred("navidrome")),
        lambda: MusicAssistant(a.ma, cred("ma")),
    ):
        try:
            target().sync(want, a.dry_run)
        except (Exception, SystemExit) as e:
            failed.append(str(e))
    if failed:
        raise SystemExit("; ".join(failed))


if __name__ == "__main__":
    main()
