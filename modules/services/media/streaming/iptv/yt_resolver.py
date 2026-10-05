#!/usr/bin/env python3
import argparse
import http.server
import json
import subprocess
import threading
import time

CACHE_SECS = 300
cache = {}
lock = threading.Lock()


def pick_live(handle, prefer):
    out = subprocess.run(
        ["yt-dlp", "--no-warnings", "--flat-playlist", "--playlist-end", "15",
         "--print", "%(id)s\t%(live_status)s\t%(title)s", f"https://www.youtube.com/@{handle}/streams"],
        capture_output=True, text=True, timeout=45,
    )
    lives = [l.split("\t", 2) for l in out.stdout.splitlines() if "\tis_live\t" in l]
    preferred = [l for l in lives if prefer and prefer.lower() in l[2].lower()]
    chosen = (preferred or lives or [None])[-1]
    return f"https://www.youtube.com/watch?v={chosen[0]}" if chosen else f"https://www.youtube.com/@{handle}/live"


def resolve(handle, prefer):
    with lock:
        hit = cache.get(handle)
        if hit and time.monotonic() - hit[0] < CACHE_SECS:
            return hit[1]
        out = subprocess.run(
            ["yt-dlp", "--no-warnings", "--no-playlist", "-j", pick_live(handle, prefer)],
            capture_output=True, text=True, timeout=45,
        )
        if out.returncode != 0:
            return None
        info = json.loads(out.stdout)
        url = next((f["manifest_url"] for f in info.get("formats", []) if f.get("manifest_url")), None)
        if url:
            cache[handle] = (time.monotonic(), url)
        return url


def make_handler(handles, m3u):
    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/news.m3u":
                try:
                    body = open(m3u, "rb").read()
                except OSError:
                    return self.send_error(404)
                self.send_response(200)
                self.send_header("Content-Type", "audio/x-mpegurl")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            parts = self.path.strip("/").split("/")
            if len(parts) != 2 or parts[0] != "yt" or parts[1] not in handles:
                return self.send_error(404)
            try:
                url = resolve(parts[1], handles[parts[1]])
            except (subprocess.TimeoutExpired, ValueError):
                url = None
            if not url:
                return self.send_error(502, "not live or resolve failed")
            self.send_response(302)
            self.send_header("Location", url)
            self.end_headers()

        def log_message(self, fmt, *args):
            print(self.address_string(), fmt % args, flush=True)

    return H


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8099)
    ap.add_argument("--allow", required=True)
    ap.add_argument("--m3u", required=True)
    a = ap.parse_args()
    handles = {}
    for line in open(a.allow):
        if line.strip() and not line.startswith("#"):
            for i in line.rstrip("\n").split("\t")[3].split(","):
                if i.startswith("yt:"):
                    handle, _, prefer = i[3:].partition("|")
                    handles[handle.lstrip("@")] = prefer
    http.server.ThreadingHTTPServer((a.bind, a.port), make_handler(handles, a.m3u)).serve_forever()
