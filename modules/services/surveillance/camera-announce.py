#!/usr/bin/env python3
"""Camera speaker over DHHTTP talk: POST /say {"text"} (Piper), /chime, /siren {"seconds"}; GET /siren.wav."""

import array
import base64
import hashlib
import io
import json
import math
import os
import re
import socket
import struct
import subprocess
import sys
import threading
import time
import wave
from functools import lru_cache
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

RATE = 16000
AAC_FRAME_SECONDS = 1024 / RATE
MEDIA_TRACK = 5
SDP_OFFER = (
    "v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=Talk\r\nc=IN IP4 0.0.0.0\r\nt=0 0\r\n"
    "m=video 0 RTP/AVP 96\r\na=control:trackID=31\r\n"
    "m=audio 0 RTP/AVP 8 96\r\na=rtpmap:8 PCMA/8000\r\na=rtpmap:96 MPEG4-GENERIC/16000/1\r\n"
    "a=control:trackID=5\r\na=sendrecv\r\n"
).encode()


def wyoming_say(host, port, text):
    """Returns (pcm, rate, width, channels) from a Wyoming TTS server."""
    pcm, fmt = bytearray(), {}
    with socket.create_connection((host, port), timeout=10) as s:
        f = s.makefile("rwb")
        f.write(json.dumps({"type": "synthesize", "data": {"text": text}}).encode() + b"\n")
        f.flush()
        while True:
            line = f.readline()
            if not line:
                raise EOFError("piper closed before audio-stop")
            ev = json.loads(line)
            data = ev.get("data") or {}
            if ev.get("data_length"):
                data.update(json.loads(f.read(ev["data_length"])))
            payload = f.read(ev["payload_length"]) if ev.get("payload_length") else b""
            if ev["type"] in ("audio-start", "audio-chunk"):
                fmt = {k: data[k] for k in ("rate", "width", "channels") if k in data} or fmt
            if ev["type"] == "audio-chunk":
                pcm += payload
            elif ev["type"] == "audio-stop":
                return bytes(pcm), fmt["rate"], fmt["width"], fmt["channels"]


def to_aac(data, *input_args):
    cmd = ["ffmpeg", "-loglevel", "error", *input_args, "-i", "-",
           "-ar", str(RATE), "-ac", "1", "-c:a", "aac", "-b:a", "32k", "-f", "adts", "-"]
    return subprocess.run(cmd, input=data, capture_output=True, check=True).stdout


def adts_frames(data):
    off = 0
    while off + 7 <= len(data):
        if data[off] != 0xFF or data[off + 1] & 0xF0 != 0xF0:
            raise ValueError(f"bad ADTS sync at {off}")
        n = ((data[off + 3] & 3) << 11) | (data[off + 4] << 3) | (data[off + 5] >> 5)
        yield data[off:off + n]
        off += n


def dhav_audio(payload, seq, tick):
    total = len(payload) + 36
    h = bytearray(28)
    struct.pack_into("<4sB3xII", h, 0, b"DHAV", 0xF0, seq, total)
    struct.pack_into("<IH", h, 0x10, int(time.time()) & 0xFFFFFFFF, tick & 0xFFFF)
    h[0x16] = 0x04
    h[0x17] = sum(h[:0x17]) & 0xFF
    h[0x18:0x1B] = b"\x83\x01\x1a"
    h[0x1B] = 4  # 16 kHz
    frame = bytes(h) + payload + b"dhav" + struct.pack("<I", total)
    return b"$" + bytes([MEDIA_TRACK * 2]) + struct.pack(">I", len(frame)) + frame


def sha1_b64(*parts):
    return base64.b64encode(hashlib.sha1("".join(parts).encode()).digest()).decode()


class Talk:
    def __init__(self, host, user, password, talk_track, port=8086):
        self.host, self.port, self.user, self.password, self.talk_track = host, port, user, password, talk_track
        self.sock = socket.create_connection((host, port), timeout=8)
        self.cseq = 0
        self.realm = None
        self.nonce = "".join(chr(97 + b % 26) for b in os.urandom(32))
        self.created = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    def close(self):
        self.sock.close()

    def digest(self):
        if self.realm:
            key = hashlib.md5(f"{self.user}:{self.realm}:{self.password}".encode()).hexdigest().upper()
            return sha1_b64(self.nonce, self.created, key)
        return sha1_b64(self.nonce, self.created, self.password)

    def path(self, track, talk=False):
        p = f"/live/visualtalk.xav?channel=1&subtype=0&encrypt=3&imagesize=18&audioType=1&trackID={track}&method=0"
        return p + "&talktype=talk" if talk else p

    def request(self, path, sdp=b""):
        for _ in range(2):
            h = [f"PLAY {path} HTTP/1.1", f"Host: {self.host}:{self.port}", "Connect-Type: P2P",
                 "Connection: keep-alive", f"Cseq: {self.cseq}", "Speed: 1.000000",
                 "User-Agent: Http Stream Client/1.0", 'Authorization: WSSE profile="UsernameToken"',
                 f'WSSE: UsernameToken Username="{self.user}", PasswordDigest="{self.digest()}", '
                 f'Nonce="{self.nonce}", Created="{self.created}"']
            if sdp:
                h += ["Accpet-Sdp: Private", "Private-Type: application/sdp", f"Private-Length: {len(sdp)}"]
            self.sock.sendall(("\r\n".join(h) + "\r\n\r\n").encode() + sdp)
            code, headers = self.read_response()
            m = re.search(r'realm="([^"]+)"', headers.get("www-authenticate", ""))
            if code == 401 and m and not self.realm:
                self.realm = m.group(1)
                continue
            if code != 200:
                raise RuntimeError(f"camera answered {code} to {path.split('?')[0]}")
            self.cseq += 1
            return headers
        raise RuntimeError("camera rejected the login")

    def read_response(self):
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise EOFError("camera closed the connection")
            buf += chunk
            while buf[:1] == b"$" and len(buf) >= 6:
                end = 6 + struct.unpack_from(">I", buf, 2)[0]
                while len(buf) < end:
                    buf += self.sock.recv(end - len(buf))
                buf = buf[end:]
        head, _, rest = buf.partition(b"\r\n\r\n")
        lines = head.decode("latin1").split("\r\n")
        headers = {k.lower(): v for k, v in (ln.split(": ", 1) for ln in lines[1:] if ": " in ln)}
        n = int(headers.get("private-length") or headers.get("content-length") or 0)
        while len(rest) < n:
            rest += self.sock.recv(n - len(rest))
        return int(lines[0].split()[1]), headers

    def speak(self, adts):
        self.request(self.path(31), SDP_OFFER)
        self.request(self.path(6))
        self.request(self.path(self.talk_track, talk=True))
        start, tick = time.monotonic(), int(time.monotonic() * 1000)
        for seq, frame in enumerate(adts_frames(adts)):
            self.sock.sendall(dhav_audio(frame, seq, tick))
            tick += int(AAC_FRAME_SECONDS * 1000)
            time.sleep(max(0, start + (seq + 1) * AAC_FRAME_SECONDS - time.monotonic()))
        time.sleep(0.5)


LOCK = threading.Lock()


def say(text):
    cfg = os.environ
    pcm, rate, _, channels = wyoming_say(cfg["PIPER_HOST"], int(cfg.get("PIPER_PORT", 10200)), text)
    speak(to_aac(pcm, "-f", "s16le", "-ar", str(rate), "-ac", str(channels)))


RATE_WAV = 22050
CHIME_NOTES = [(1046.5, 0.0), (784.0, 0.3), (1046.5, 0.6), (784.0, 0.9)]
BELL_PARTIALS = ((1.0, 1.0), (2.0, 0.5), (2.76, 0.35), (5.4, 0.15))


def wav_bytes(samples):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE_WAV)
        w.writeframes(array.array("h", samples).tobytes())
    return buf.getvalue()


@lru_cache(maxsize=8)
def siren_wav(seconds):
    phase, samples = 0.0, []
    for i in range(RATE_WAV * seconds):
        phase += 2 * math.pi * (650 + 850 * (i / RATE_WAV % 0.4) / 0.4) / RATE_WAV
        samples.append(int(20000 * math.sin(phase)))
    return wav_bytes(samples)


@lru_cache(maxsize=1)
def chime_wav():
    ring = int(RATE_WAV * 1.6)
    mix = [0.0] * (int(CHIME_NOTES[-1][1] * RATE_WAV) + ring)
    for freq, start in CHIME_NOTES:
        offset = int(start * RATE_WAV)
        for i in range(ring):
            t = i / RATE_WAV
            env = math.exp(-3 * t) * min(1.0, t / 0.005)
            mix[offset + i] += env * sum(a * math.sin(2 * math.pi * freq * k * t) for k, a in BELL_PARTIALS)
    peak = max(abs(v) for v in mix)
    return wav_bytes(int(20000 * v / peak) for v in mix)


def siren_seconds(value):
    seconds = int(value)
    if not 1 <= seconds <= 30:
        raise ValueError("seconds must be 1-30")
    return seconds


def speak(adts):
    cfg = os.environ
    with LOCK:
        talk = Talk(cfg["CAMERA_HOST"], cfg["CAMERA_USER"], cfg["CAMERA_PASSWORD"], int(cfg.get("TALK_TRACK", 64)))
        try:
            talk.speak(adts)
        finally:
            talk.close()


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            if self.path not in ("/say", "/siren", "/chime"):
                return self.reply(404, "not found")
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
            if self.path == "/chime":
                speak(to_aac(chime_wav()))
                return self.reply(200, "ok")
            if self.path == "/siren":
                speak(to_aac(siren_wav(siren_seconds(body.get("seconds", 10)))))
                return self.reply(200, "ok")
            text = str(body.get("text", "")).strip()
            if not text or len(text) > 500:
                return self.reply(400, "text must be 1-500 characters")
            say(text)
            self.reply(200, "ok")
        except ValueError as e:
            self.reply(400, str(e))
        except Exception as e:
            print(f"say failed: {e!r}", file=sys.stderr, flush=True)
            self.reply(502, str(e))

    def do_GET(self):
        url = urlparse(self.path)
        try:
            if url.path != "/siren.wav":
                return self.reply(404, "not found")
            data = siren_wav(siren_seconds(parse_qs(url.query).get("seconds", ["10"])[0]))
        except ValueError as e:
            return self.reply(400, str(e))
        self.send_response(200)
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def reply(self, code, msg):
        body = json.dumps({"result": msg}).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def self_check():
    frame = dhav_audio(b"\x00" * 19, 1, 0x5566)
    assert frame[:2] == b"$\x0a" and frame[6:10] == b"DHAV" and frame[-8:-4] == b"dhav"
    assert struct.unpack_from("<I", frame, 6 + 12)[0] == 55
    adts = bytes.fromhex("fff15040035ffc") + b"\x00" * 19
    assert list(adts_frames(adts + adts)) == [adts, adts]
    assert sha1_b64("a", "b", "c") == base64.b64encode(hashlib.sha1(b"abc").digest()).decode()
    wav = wave.open(io.BytesIO(siren_wav(2)))
    assert wav.getnframes() == 2 * 22050 and wav.getframerate() == 22050
    assert wave.open(io.BytesIO(chime_wav())).getnframes() > 22050
    print("ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["--check"]:
        self_check()
    else:
        host, port = os.environ["LISTEN"].rsplit(":", 1)
        ThreadingHTTPServer((host, int(port)), Handler).serve_forever()
