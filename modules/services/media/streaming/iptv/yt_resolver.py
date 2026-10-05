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


def resolve(handle):
    with lock:
        hit = cache.get(handle)
        if hit and time.monotonic() - hit[0] < CACHE_SECS:
            return hit[1]
        out = subprocess.run(
            ["yt-dlp", "--no-warnings", "--no-playlist", "-j", f"https://www.youtube.com/@{handle}/live"],
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
                url = resolve(parts[1])
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
    handles = set()
    for line in open(a.allow):
        if line.strip() and not line.startswith("#"):
            handles |= {i[4:].lstrip("@") for i in line.rstrip("\n").split("\t")[-1].split(",") if i.startswith("yt:")}
    http.server.ThreadingHTTPServer((a.bind, a.port), make_handler(handles, a.m3u)).serve_forever()
