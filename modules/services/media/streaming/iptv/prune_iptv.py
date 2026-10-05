#!/usr/bin/env python3
import argparse
import concurrent.futures as cf
import http.client
import json
import os
import re
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://iptv-org.github.io/iptv"
LISTS = ["languages/mal", "countries/in", "categories/news", "categories/business"]
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/122 Safari/537.36"
FLOOR = 720
TIMEOUT = 10
DROP_AFTER = 3
SWITCH_AFTER = 2
MIN_CHANNELS = 8


def fetch(url, ua=UA, ref=None, rng=None, limit=2_000_000):
    headers = {"User-Agent": ua}
    if ref:
        headers["Referer"] = ref
    if rng:
        headers["Range"] = rng
    start = time.monotonic()
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=TIMEOUT) as r:
            return r.status, r.read(limit), time.monotonic() - start
    except urllib.error.HTTPError as e:
        return e.code, b"", time.monotonic() - start
    except (urllib.error.URLError, http.client.HTTPException, OSError, ValueError):
        return 0, b"", time.monotonic() - start


def parse_m3u(text):
    out, cur = {}, None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("#EXTINF"):
            attr = lambda k: (re.search(k + r'="([^"]*)"', line) or [None, ""])[1]
            name = line.rsplit(",", 1)[-1].strip()
            lab = re.search(r"\((\d+)p\)", name)
            cur = {
                "id": attr("tvg-id"),
                "logo": attr("tvg-logo"),
                "ua": attr("http-user-agent") or UA,
                "ref": attr("http-referrer") or None,
                "label": int(lab[1]) if lab else 0,
            }
        elif line.startswith("#EXTVLCOPT:") and cur:
            k, _, v = line[len("#EXTVLCOPT:"):].partition("=")
            if k == "http-user-agent":
                cur["ua"] = v
            elif k == "http-referrer":
                cur["ref"] = v
        elif line.startswith("http") and cur:
            cur["url"] = line
            out.setdefault(cur["id"], cur)
            cur = None
    return out


SHORTENERS = ("short.gy", "bit.ly", "tinyurl.com", "t.co", "rb.gy", "cutt.ly", "is.gd")


def unofficial(url):
    host = urllib.parse.urlparse(url).hostname or ""
    return bool(re.fullmatch(r"[\d.]+", host)) or any(host == s or host.endswith("." + s) for s in SHORTENERS)


def probe(e):
    if not e.get("trusted") and unofficial(e["url"]):
        return {"ok": False, "why": "raw-ip/shortener"}
    r = probe_once(e)
    if not r["ok"] and r["why"].endswith(" 0"):
        r = probe_once(e)
    return r


def probe_once(e):
    ua, ref = e["ua"], e["ref"]
    code, body, secs = fetch(e["url"], ua, ref)
    if code != 200:
        return {"ok": False, "why": f"master {code}"}
    text = body.decode("utf-8", "replace").replace("\r", "")
    if text.lstrip().startswith("<MPD") or "<MPD" in text[:400]:
        if 'type="dynamic"' not in text:
            return {"ok": False, "why": "dash not live"}
        heights = [int(h) for h in re.findall(r'height="(\d+)"', text)]
        return {"ok": True, "why": "dash", "height": max(heights, default=e["label"]), "bw": 0, "ms": int(secs * 1000)}
    if not text.startswith("#EXTM3U"):
        return {"ok": False, "why": "not m3u8"}
    height = bw = 0
    cur_url = e["url"]
    if "#EXT-X-STREAM-INF" in text:
        best, lines = None, text.split("\n")
        for i, l in enumerate(lines):
            if l.startswith("#EXT-X-STREAM-INF"):
                b = re.search(r"BANDWIDTH=(\d+)", l)
                r = re.search(r"RESOLUTION=\d+x(\d+)", l)
                uri = next((x for x in lines[i + 1:] if x and not x.startswith("#")), None)
                cand = (int(b[1]) if b else 0, int(r[1]) if r else 0, uri)
                if uri and (best is None or cand[0] >= best[0]):
                    best = cand
        if not best:
            return {"ok": False, "why": "no variants"}
        bw, height, uri = best
        cur_url = urllib.parse.urljoin(e["url"], uri)
        code, body, _ = fetch(cur_url, ua, ref)
        if code != 200:
            return {"ok": False, "why": f"chunklist {code}"}
        text = body.decode("utf-8", "replace").replace("\r", "")
    if "#EXTINF" not in text:
        return {"ok": False, "why": "no segments"}
    seg = next((x for x in text.split("\n") if x and not x.startswith("#")), None)
    code, _, _ = fetch(urllib.parse.urljoin(cur_url, seg), ua, ref, rng="bytes=0-2047")
    if code not in (200, 206):
        return {"ok": False, "why": f"segment {code}"}
    return {"ok": True, "why": "ok", "height": height or e["label"], "bw": bw, "ms": int(secs * 1000)}


def tier(h):
    return 3 if h >= 1080 else 2 if h >= 720 else 1 if h >= 540 else 0


GROUP = {"biz": "Business", "ml": "Malayalam News"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--allow", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--state", required=True)
    ap.add_argument("--yt-base")
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()

    entries = {}
    for l in LISTS:
        code, body, _ = fetch(f"{BASE}/{l}.m3u", limit=50_000_000)
        if code != 200:
            sys.exit(f"fetch {l} failed ({code}); output left untouched")
        for k, v in parse_m3u(body.decode("utf-8", "replace")).items():
            entries.setdefault(k, v)

    allow = []
    for line in open(a.allow):
        if line.strip() and not line.startswith("#"):
            ch, slot, needed, ids = (line.rstrip("\n").split("\t") + [""] * 4)[:4]
            allow.append((ch, slot, bool(needed), [i for i in ids.split(",") if i]))

    for _, _, _, ids in allow:
        for i in ids:
            if i.startswith("yt:") and a.yt_base:
                url = f"{a.yt_base}/yt/{i[3:].split('|')[0].lstrip('@')}"
                entries[i] = {"id": i, "logo": "", "ua": UA, "ref": None, "label": 0, "url": url, "trusted": True}

    jobs = {(ch, i): entries[i] for ch, _, _, ids in allow for i in ids if i in entries}
    for ch, _, _, ids in allow:
        for i in ids:
            if i not in entries:
                print(f"note: {i} not in any list", file=sys.stderr)
    with cf.ThreadPoolExecutor(16) as ex:
        results = dict(zip(jobs, ex.map(probe, jobs.values())))

    try:
        state = json.load(open(a.state))
    except (OSError, ValueError):
        state = {}

    chosen, report = [], []
    for ch, slot, needed, ids in allow:
        ok = []
        for order, i in enumerate(ids):
            r = results.get((ch, i))
            if r and r["ok"] and (r["height"] >= FLOOR or needed or r["height"] == 0):
                ok.append((-r["height"], -r["bw"], order, i))
        ok.sort()
        best = ok[0][3] if ok else None
        st = state.get(ch, {"id": None, "fails": 0, "chal": None, "runs": 0})
        cur = st["id"]
        cur_ok = cur and (ch, cur) in results and results[(ch, cur)]["ok"]
        note = ""
        if cur_ok:
            st["fails"] = 0
            if best and best != cur and tier(results[(ch, best)]["height"]) > tier(results[(ch, cur)]["height"]):
                st["runs"] = st["runs"] + 1 if st["chal"] == best else 1
                st["chal"] = best
                if st["runs"] >= SWITCH_AFTER:
                    cur, st["chal"], st["runs"], note = best, None, 0, "upgraded"
                else:
                    note = f"upgrade pending {best}"
            else:
                st["chal"], st["runs"] = None, 0
        elif best:
            cur, st["fails"], st["chal"], st["runs"] = best, 0, None, 0
            note = "switched" if st["id"] else "new"
        elif cur and (ch, cur) in results:
            st["fails"] += 1
            note = f"failing {st['fails']}/{DROP_AFTER}: {results[(ch, cur)]['why']}"
            if st["fails"] >= DROP_AFTER:
                cur = None
        else:
            cur = None
        st["id"] = cur
        state[ch] = st
        if cur:
            r = results[(ch, cur)]
            chosen.append((ch, slot, cur, entries[cur]))
            report.append((ch, "ON", cur, r.get("height", "-"), r.get("bw", "-"), note or r["why"]))
        else:
            why = "; ".join(f"{i}: {results[(ch, i)]['why']}" for i in ids if (ch, i) in results) or "no source"
            report.append((ch, "OFF", "-", "-", "-", why))

    for row in report:
        print("\t".join(str(x) for x in row))
    print(f"\nlive: {len(chosen)}/{len(allow)}", file=sys.stderr)

    if a.dry:
        return
    if len(chosen) < MIN_CHANNELS:
        sys.exit(f"only {len(chosen)} channels live; refusing to overwrite output")
    lines = ["#EXTM3U"]
    for n, (ch, slot, cid, e) in enumerate(chosen, 1):
        grp = GROUP.get(slot.split("-")[0], "News")
        base = re.sub(r"\W+", "", ch) if cid.startswith("yt:") else cid.split("@")[0]
        lines.append(f'#EXTINF:-1 tvg-id="{base}" tvg-chno="{n}" tvg-logo="{e["logo"]}" group-title="{grp}",{ch}')
        if e["ua"] != UA:
            lines.append(f'#EXTVLCOPT:http-user-agent={e["ua"]}')
        if e["ref"]:
            lines.append(f'#EXTVLCOPT:http-referrer={e["ref"]}')
        lines.append(e["url"])
    for path, data in ((a.out, "\n".join(lines) + "\n"), (a.state, json.dumps(state, indent=1))):
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(path)))
        with os.fdopen(fd, "w") as f:
            f.write(data)
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)


if __name__ == "__main__":
    main()
