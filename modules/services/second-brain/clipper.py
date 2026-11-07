"""Clipper: turn a shared video link (Instagram reel, YouTube, ...) into an Obsidian note.

POST /clip {"url": "..."} with "Authorization: Bearer <token>" queues a job and returns 202
at once; a single worker thread then
  1. reads the post's metadata with yt-dlp (title, author, caption/description),
  2. takes the transcript from existing subtitles when the platform has them, otherwise
     downloads the audio and transcribes it with faster-whisper,
  3. asks Claude for a title, summary, key points and candidate evergreen ideas (structured
     JSON output),
  4. writes the note into the vault's inbox, atomically, so Obsidian Sync never uploads
     half a file.
Jobs are files under STATE_DIR/queue, so a restart resumes them. A job that keeps failing
still produces a short note saying so, so nothing shared from the phone vanishes silently.

Notes follow the vault rules (docs/second-brain-starter/CLAUDE.md): a capture in `0 Inbox`
named `YYYY-MM-DD HHMM <title>.md`, frontmatter `created` + `type: capture`, no topic tags.
"""

import datetime
import hmac
import json
import logging
import os
import queue
import re
import shutil
import subprocess
import tempfile
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse, urlunparse

import anthropic

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger("clipper")

VAULT = Path(os.environ["VAULT_DIR"]).resolve()
INBOX = os.environ.get("INBOX_FOLDER", "0 Inbox")
STATE = Path(os.environ["STATE_DIR"])
PORT = int(os.environ["PORT"])
WHISPER_MODEL = os.environ.get("WHISPER_MODEL", "small")
SUMMARY_MODEL = os.environ.get("SUMMARY_MODEL", "claude-haiku-5-5")
MAX_DURATION = int(os.environ.get("MAX_DURATION_SECONDS", "7200"))
MAX_ATTEMPTS = 3
CREDS = Path(os.environ["CREDENTIALS_DIRECTORY"])

QUEUE_DIR = STATE / "queue"
WORK_DIR = STATE / "work"
INDEX_FILE = STATE / "index.json"  # normalised URL -> vault-relative note path

TOKEN = (CREDS / "token").read_text().strip()
COOKIES = CREDS / "cookies" if (CREDS / "cookies").exists() else None
claude = anthropic.Anthropic(api_key=(CREDS / "anthropic-api-key").read_text().strip())

jobs: "queue.Queue[str]" = queue.Queue()
index_lock = threading.Lock()


# ---------------------------------------------------------------- helpers


def normalise_url(url: str) -> str:
    """Strip tracking params so the same reel shared twice is recognised."""
    u = urlparse(url.strip())
    host = u.netloc.lower().removeprefix("www.").removeprefix("m.")
    if host == "youtu.be":
        return f"https://youtube.com/watch?v={u.path.lstrip('/')}"
    if host.endswith("youtube.com"):
        if u.path.startswith("/shorts/"):
            return f"https://youtube.com/watch?v={u.path.split('/')[2]}"
        v = parse_qs(u.query).get("v")
        if v:
            return f"https://youtube.com/watch?v={v[0]}"
    return urlunparse(("https", host, u.path.rstrip("/"), "", "", ""))


def load_index() -> dict:
    try:
        return json.loads(INDEX_FILE.read_text())
    except FileNotFoundError:
        return {}


def save_index(index: dict) -> None:
    tmp = INDEX_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(index, indent=1, sort_keys=True))
    os.replace(tmp, INDEX_FILE)


def write_atomic(path: Path, text: str) -> None:
    """Write via a temp file in STATE (same filesystem), never visible inside the vault."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=WORK_DIR, prefix="note-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.chmod(tmp, 0o660)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def unique_note_path(title: str, when: datetime.datetime) -> Path:
    slug = re.sub(r'[\\/:*?"<>|#^\[\]]+', "", title).strip()
    slug = re.sub(r"\s+", " ", slug)[:80].rstrip(" .") or "Clip"
    base = VAULT / INBOX / f"{when:%Y-%m-%d %H%M} {slug}"
    path, n = base.with_suffix(".md"), 2
    while path.exists():
        path, n = Path(f"{base} ({n}).md"), n + 1
    return path


def yaml_str(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)  # JSON strings are valid YAML scalars


def yt_dlp(*args: str, cwd: Path) -> subprocess.CompletedProcess:
    cmd = ["yt-dlp", "--no-playlist", "--no-progress", "--no-warnings", *args]
    if COOKIES:
        cmd[1:1] = ["--cookies", str(COOKIES)]
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=900, check=True)


# ---------------------------------------------------------------- transcript


def vtt_to_text(vtt: str) -> str:
    """Flatten WebVTT; auto-captions repeat each line as it scrolls, so drop repeats."""
    out: list[str] = []
    for line in vtt.splitlines():
        line = line.strip()
        if not line or "-->" in line or line.startswith(("WEBVTT", "Kind:", "Language:", "NOTE")):
            continue
        if line.isdigit():
            continue
        line = re.sub(r"<[^>]+>", "", line).strip()
        if line and (not out or out[-1] != line):
            out.append(line)
    return " ".join(out)


def subtitles_transcript(meta: dict, work: Path) -> str | None:
    lang = (meta.get("language") or "en").split("-")[0]
    for key, kind in (("subtitles", "--write-subs"), ("automatic_captions", "--write-auto-subs")):
        tracks = meta.get(key) or {}
        pick = next((t for t in tracks if t == lang or t.startswith(lang + "-")), None)
        if pick is None and key == "subtitles":
            pick = next((t for t in tracks if t.startswith("en")), None)
        if pick is None:
            continue
        yt_dlp(kind, "--skip-download", "--sub-langs", pick, "--sub-format", "vtt",
               "-o", "subs", meta["webpage_url"], cwd=work)
        for f in work.glob("subs*.vtt"):
            text = vtt_to_text(f.read_text(encoding="utf-8", errors="replace"))
            if len(text) > 20:
                return text
    return None


_whisper = None


def whisper_transcript(url: str, work: Path) -> tuple[str, str]:
    global _whisper
    from faster_whisper import WhisperModel  # heavy import; only when needed

    yt_dlp("-f", "bestaudio/best", "-o", "audio.%(ext)s", url, cwd=work)
    audio = next(work.glob("audio.*"))
    if _whisper is None:
        log.info("loading whisper model %s", WHISPER_MODEL)
        _whisper = WhisperModel(WHISPER_MODEL, device="cpu", compute_type="int8",
                                download_root=str(STATE / "models"))
    segments, info = _whisper.transcribe(str(audio), vad_filter=True, beam_size=5)
    return " ".join(s.text.strip() for s in segments).strip(), info.language


# ---------------------------------------------------------------- summary

NOTE_SCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string", "description": "Short, specific note title (max ~8 words)."},
        "summary": {"type": "string", "description": "2-4 sentence summary of the content."},
        "key_points": {"type": "array", "items": {"type": "string"}},
        "candidate_ideas": {"type": "array", "items": {"type": "string"},
                            "description": "0-3 claims from the video worth an evergreen note, "
                                           "each phrased as a full claim in sentence case."},
    },
    "required": ["title", "summary", "key_points", "candidate_ideas"],
    "additionalProperties": False,
}

SYSTEM = (
    "You turn a transcript of a short video into a note for the user's Obsidian second brain. "
    "Write in English even when the video is in another language. Capture the substance: "
    "facts, steps, recommendations, numbers, names. Leave out filler, greetings, and calls "
    "to like or subscribe. If the transcript is empty or meaningless (music only), say so "
    "in the summary and base the note on the caption. Candidate ideas are suggestions only: "
    "the user writes evergreen notes in their own words, so list claims, never draft their notes."
)


def summarise(meta: dict, transcript: str) -> dict:
    prompt = (
        f"Platform: {meta.get('extractor_key', '')}\n"
        f"Author: {meta.get('uploader') or meta.get('channel') or ''}\n"
        f"Original title: {meta.get('title') or ''}\n"
        f"Caption / description:\n{(meta.get('description') or '').strip()}\n\n"
        f"Transcript:\n{transcript or '(no speech)'}"
    )
    resp = claude.messages.create(
        model=SUMMARY_MODEL,
        max_tokens=16000,
        system=SYSTEM,
        messages=[{"role": "user", "content": prompt}],
        output_config={"effort": "low", "format": {"type": "json_schema", "schema": NOTE_SCHEMA}},
    )
    if resp.stop_reason == "refusal":
        raise RuntimeError(f"summary refused: {resp.stop_details}")
    if resp.stop_reason == "max_tokens":
        raise RuntimeError("summary hit max_tokens")
    return json.loads(next(b.text for b in resp.content if b.type == "text"))


# ---------------------------------------------------------------- note


def render_note(url: str, meta: dict, note: dict, transcript: str, source: str,
                when: datetime.datetime) -> str:
    upload = meta.get("upload_date")
    fm = [
        "---",
        f"created: {when:%Y-%m-%dT%H:%M}",
        "type: capture",
        f"source: {yaml_str(meta.get('webpage_url') or url)}",
        "kind: video",
        f"platform: {yaml_str(meta.get('extractor_key') or '')}",
        f"author: {yaml_str(meta.get('uploader') or meta.get('channel') or '')}",
    ]
    if upload:
        fm.append(f"published: {upload[:4]}-{upload[4:6]}-{upload[6:]}")
    if meta.get("duration"):
        fm.append(f"duration: {int(meta['duration'])}")
    fm += [f"transcript: {yaml_str(source)}", "---"]
    body = [
        f"# {note['title']}",
        "",
        "## Summary",
        "<!-- Drafted by Claude from the transcript; rewrite it in your words when you file it. -->",
        note["summary"].strip(),
        "",
        "## Key points",
        *[f"- {p.strip()}" for p in note["key_points"]],
        "",
    ]
    if note["candidate_ideas"]:
        body += ["## Ideas for evergreen notes", *[f"- [ ] {i.strip()}" for i in note["candidate_ideas"]], ""]
    desc = (meta.get("description") or "").strip()
    if desc:
        # Escape hashtags: Obsidian would turn them into topic tags, which the vault rules forbid.
        desc = re.sub(r"(?<!\S)#(?=\w)", r"\\#", desc)
        body += ["## Caption", "", "> " + desc.replace("\n", "\n> "), ""]
    body += ["## Transcript", "", transcript.strip() or "_(no speech)_", ""]
    return "\n".join(fm + [""] + body)


def failure_note(url: str, error: str, when: datetime.datetime) -> str:
    return "\n".join([
        "---",
        f"created: {when:%Y-%m-%dT%H:%M}",
        "type: capture",
        f"source: {yaml_str(url)}",
        "clip: failed",
        "---",
        "",
        "# Clip failed",
        "",
        f"Couldn't transcribe <{url}>.",
        "",
        "```",
        error.strip()[-2000:],
        "```",
        "",
    ])


# ---------------------------------------------------------------- worker


def process(job_file: Path) -> None:
    job = json.loads(job_file.read_text())
    url, key = job["url"], normalise_url(job["url"])
    when = datetime.datetime.now().astimezone()
    work = Path(tempfile.mkdtemp(dir=WORK_DIR, prefix="job-"))
    try:
        meta = json.loads(yt_dlp("--dump-single-json", "--skip-download", url, cwd=work).stdout)
        if (meta.get("duration") or 0) > MAX_DURATION:
            raise RuntimeError(f"video is {meta['duration']}s long; limit is {MAX_DURATION}s")
        transcript = subtitles_transcript(meta, work)
        source = "subtitles"
        if transcript is None:
            transcript, lang = whisper_transcript(meta.get("webpage_url") or url, work)
            source = f"whisper-{WHISPER_MODEL} ({lang})"
        note = summarise(meta, transcript)
        path = unique_note_path(note["title"], when)
        write_atomic(path, render_note(url, meta, note, transcript, source, when))
        rel = str(path.relative_to(VAULT))
        with index_lock:
            index = load_index()
            index[key] = rel
            save_index(index)
        log.info("clipped %s -> %s (%s)", url, rel, source)
        job_file.unlink()
    except Exception as e:  # noqa: BLE001 -- every failure is retried, then reported as a note
        detail = e.stderr if isinstance(e, subprocess.CalledProcessError) else repr(e)
        job["attempts"] = job.get("attempts", 0) + 1
        log.error("job %s attempt %d failed: %s", job_file.stem, job["attempts"], detail)
        if job["attempts"] >= MAX_ATTEMPTS:
            path = unique_note_path("Clip failed", when)
            write_atomic(path, failure_note(url, str(detail), when))
            job_file.unlink()
        else:
            job_file.write_text(json.dumps(job))
            threading.Timer(60 * job["attempts"], jobs.put, [job_file.name]).start()
    finally:
        shutil.rmtree(work, ignore_errors=True)


def worker() -> None:
    while True:
        name = jobs.get()
        f = QUEUE_DIR / name
        if f.exists():
            process(f)


# ---------------------------------------------------------------- http


class Handler(BaseHTTPRequestHandler):
    server_version = "clipper"

    def _send(self, code: int, body: dict) -> None:
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        if self.path == "/health":
            self._send(200, {"ok": True, "queued": len(list(QUEUE_DIR.glob("*.json")))})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self) -> None:
        if self.path != "/clip":
            return self._send(404, {"error": "not found"})
        auth = self.headers.get("Authorization", "")
        if not hmac.compare_digest(auth.encode(), f"Bearer {TOKEN}".encode()):
            return self._send(401, {"error": "unauthorized"})
        try:
            length = min(int(self.headers.get("Content-Length", "0")), 64 * 1024)
            raw = self.rfile.read(length).decode()
            body = json.loads(raw) if raw.lstrip().startswith("{") else {"url": raw}
            # The share sheet often hands over "caption text https://..." -- take the first link.
            m = re.search(r"https?://\S+", str(body.get("url", "")))
            if not m:
                raise ValueError("no URL in request")
            url = m.group(0)
        except (ValueError, json.JSONDecodeError) as e:
            return self._send(400, {"error": str(e)})
        key = normalise_url(url)
        with index_lock:
            existing = load_index().get(key)
        if existing and (VAULT / existing).exists() and not body.get("force"):
            return self._send(200, {"status": "exists", "note": existing})
        job_id = uuid.uuid4().hex[:12]
        (QUEUE_DIR / f"{job_id}.json").write_text(json.dumps({"url": url}))
        jobs.put(f"{job_id}.json")
        log.info("queued %s as %s", url, job_id)
        self._send(202, {"status": "queued", "id": job_id})

    def log_message(self, fmt: str, *args) -> None:  # route access log through logging
        log.info("%s %s", self.address_string(), fmt % args)


def main() -> None:
    for d in (QUEUE_DIR, WORK_DIR, STATE / "models"):
        d.mkdir(parents=True, exist_ok=True)
    for stale in WORK_DIR.iterdir():  # leftovers from a crash
        shutil.rmtree(stale, ignore_errors=True) if stale.is_dir() else stale.unlink()
    for f in sorted(QUEUE_DIR.glob("*.json"), key=lambda p: p.stat().st_mtime):
        jobs.put(f.name)
    threading.Thread(target=worker, daemon=True).start()
    log.info("listening on 127.0.0.1:%d, vault %s", PORT, VAULT)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
