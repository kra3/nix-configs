"""Remote MCP server exposing the Obsidian vault to Claude (claude.ai web/mobile, Claude Code).

Auth: FastMCP's OIDCProxy fronts Authelia, so claude.ai's dynamic client registration works
against Authelia's single static client. Only the admin group passes (Authelia policy).
Every path is confined to VAULT_DIR; dot-folders (.obsidian, .trash) are never touched.
Writes are atomic (temp file + rename) so the headless Obsidian Sync never uploads half a note.
"""

import datetime
import hashlib
import os
import re
import tempfile
from pathlib import Path

from fastmcp import FastMCP
from fastmcp.server.auth.oidc_proxy import OIDCProxy

VAULT = Path(os.environ["VAULT_DIR"]).resolve()
INBOX = os.environ.get("INBOX_FOLDER", "0 Inbox")
PUBLIC_URL = os.environ["PUBLIC_URL"].rstrip("/")
PORT = int(os.environ["PORT"])
MAX_READ_BYTES = 512 * 1024
# Open only while connecting a new Claude client; closed, nobody can register (DCR) or use a
# URL client id (CIMD), so a phished authorize link has no client of the attacker to land on.
ALLOW_NEW_CLIENTS = os.environ.get("ALLOW_NEW_CLIENTS", "0") == "1"


def _secret(name: str) -> str:
    return (Path(os.environ["CREDENTIALS_DIRECTORY"]) / name).read_text().strip()


CLIENT_SECRET = _secret("oidc-client-secret")

auth = OIDCProxy(
    config_url=os.environ["OIDC_DISCOVERY_URL"],
    client_id=os.environ["OIDC_CLIENT_ID"],
    client_secret=CLIENT_SECRET,
    # Stable across restarts, so issued tokens and the encrypted client store stay valid.
    jwt_signing_key=hashlib.sha256(b"second-brain-mcp-jwt:" + CLIENT_SECRET.encode()).hexdigest(),
    # Authelia's access tokens are opaque by default; its id_token is always a JWKS-verifiable JWT.
    verify_id_token=True,
    # Not checked against the id_token (it has no scope claim), only requested upstream and advertised.
    required_scopes=["openid", "profile", "email", "groups"],
    base_url=PUBLIC_URL,
    # Authelia rejects RFC 8707 resource indicators it has no audience registered for.
    forward_resource=False,
    token_endpoint_auth_method="client_secret_basic",
    # Dynamic registration is open (claude.ai needs it), so every new client must be approved on
    # FastMCP's own consent page before the upstream Authelia hop; never rely on the default.
    require_authorization_consent=True,
    enable_cimd=ALLOW_NEW_CLIENTS,
    allowed_client_redirect_uris=[
        "https://claude.ai/api/mcp/auth_callback",
        "https://claude.com/api/mcp/auth_callback",
        # Claude Code's local OAuth callback.
        "http://localhost:*",
        "http://127.0.0.1:*",
    ],
)
# OAuthProxy always enables DCR; routes are built from this at startup.
auth.client_registration_options.enabled = ALLOW_NEW_CLIENTS

mcp = FastMCP(
    "second-brain",
    instructions=(
        "Arun's Obsidian vault (PARA layout: '0 Inbox', '1 Projects', '2 Areas', '3 Resources', "
        "'4 Archive'). If CLAUDE.md exists at the vault root, read it first for filing and naming rules. "
        "Paths are relative to the vault root. New, unsorted captures go to the inbox via capture."
    ),
    auth=auth,
)


class VaultError(ValueError):
    pass


def _resolve(rel: str, *, must_exist: bool = True) -> Path:
    rel = rel.strip().lstrip("/")
    parts = Path(rel).parts
    if any(p.startswith(".") for p in parts):
        raise VaultError(f"hidden paths are off limits: {rel}")
    path = (VAULT / rel).resolve()
    if path != VAULT and VAULT not in path.parents:
        raise VaultError(f"path escapes the vault: {rel}")
    if must_exist and not path.exists():
        raise VaultError(f"not found: {rel}")
    return path


def _note(rel: str, *, must_exist: bool = True) -> Path:
    if not rel.endswith(".md"):
        rel += ".md"
    path = _resolve(rel, must_exist=must_exist)
    if path.exists() and not path.is_file():
        raise VaultError(f"not a file: {rel}")
    return path


def _rel(path: Path) -> str:
    return str(path.relative_to(VAULT))


def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".mcp-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


def _visible_notes(root: Path):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for name in sorted(filenames):
            if name.endswith(".md") and not name.startswith("."):
                yield Path(dirpath) / name


READ_ONLY = {"readOnlyHint": True, "openWorldHint": False}
WRITES = {"readOnlyHint": False, "destructiveHint": False, "openWorldHint": False}


@mcp.tool(annotations=READ_ONLY)
def list_notes(folder: str = "", recursive: bool = True) -> list[str]:
    """List notes (vault-relative .md paths) under a folder; empty folder means the vault root."""
    root = _resolve(folder)
    if recursive:
        return [_rel(p) for p in _visible_notes(root)]
    return sorted(
        _rel(p) for p in root.iterdir() if not p.name.startswith(".") and (p.is_dir() or p.suffix == ".md")
    )


@mcp.tool(annotations=READ_ONLY)
def read_note(path: str) -> str:
    """Return the full Markdown of one note."""
    note = _note(path)
    if note.stat().st_size > MAX_READ_BYTES:
        raise VaultError(f"{path} is larger than {MAX_READ_BYTES} bytes")
    return note.read_text(encoding="utf-8")


@mcp.tool(annotations=READ_ONLY)
def search_notes(query: str, folder: str = "", limit: int = 20) -> list[dict]:
    """Case-insensitive search of note names and contents. Every word in the query must appear.

    Returns path plus up to three matching lines per note, best matches (most hits) first.
    """
    words = [w.lower() for w in query.split() if w]
    if not words:
        raise VaultError("empty query")
    hits = []
    for note in _visible_notes(_resolve(folder)):
        try:
            text = note.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        haystack = (_rel(note) + "\n" + text).lower()
        if not all(w in haystack for w in words):
            continue
        lines = [ln.strip() for ln in text.splitlines() if any(w in ln.lower() for w in words)]
        score = sum(haystack.count(w) for w in words)
        hits.append({"path": _rel(note), "score": score, "lines": lines[:3]})
    hits.sort(key=lambda h: -h["score"])
    return hits[: max(1, min(limit, 100))]


@mcp.tool(annotations=WRITES)
def write_note(path: str, content: str, overwrite: bool = False) -> str:
    """Create a note, or replace one when overwrite is true. Returns the vault-relative path."""
    note = _note(path, must_exist=False)
    if note.exists() and not overwrite:
        raise VaultError(f"{_rel(note)} exists; pass overwrite=true to replace it")
    _atomic_write(note, content)
    return _rel(note)


@mcp.tool(annotations=WRITES)
def append_to_note(path: str, content: str) -> str:
    """Append Markdown to the end of a note, creating it if missing."""
    note = _note(path, must_exist=False)
    existing = note.read_text(encoding="utf-8") if note.exists() else ""
    sep = "" if not existing or existing.endswith("\n\n") else ("\n" if existing.endswith("\n") else "\n\n")
    _atomic_write(note, existing + sep + content.rstrip("\n") + "\n")
    return _rel(note)


@mcp.tool(annotations=WRITES)
def capture(text: str, title: str = "") -> str:
    """Quick capture: save text as a new timestamped note in the inbox. Returns its path."""
    now = datetime.datetime.now().astimezone()
    slug = re.sub(r"[^\w\- ]+", "", title).strip()[:60] or "capture"
    name = f"{now:%Y-%m-%d %H%M} {slug}.md"
    note = _note(f"{INBOX}/{name}", must_exist=False)
    body = f"---\ncreated: {now.isoformat(timespec='seconds')}\nsource: claude\n---\n\n{text.rstrip()}\n"
    _atomic_write(note, body)
    return _rel(note)


@mcp.tool(annotations=WRITES)
def move_note(source: str, destination: str) -> str:
    """Move or rename a note (e.g. file it from the inbox into PARA). Refuses to overwrite."""
    src = _note(source)
    dst = _note(destination, must_exist=False)
    if dst.exists():
        raise VaultError(f"{_rel(dst)} already exists")
    dst.parent.mkdir(parents=True, exist_ok=True)
    os.rename(src, dst)
    return _rel(dst)


if __name__ == "__main__":
    mcp.run(
        transport="http",
        host="127.0.0.1",
        port=PORT,
        path="/mcp",
        show_banner=False,
    )
