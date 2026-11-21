import argparse
import asyncio
import datetime as dt
import json
import logging
import os
import urllib.error
import urllib.parse
import urllib.request

log = logging.getLogger("media-bot")

STATE_MISSING = "missing"
STATE_DOWNLOADING = "downloading"
STATE_ON_DISK = "on_disk"
STATE_KEPT = "kept"

SEERR_PENDING = 2
SEERR_PROCESSING = 3

TG_TEXT_LIMIT = 4096
TG_BUTTONS_PER_MESSAGE = 50


class Unreachable(Exception):
    def __init__(self, app):
        super().__init__(app)
        self.app = app


class Redact(logging.Filter):
    def __init__(self, secrets):
        super().__init__()
        self.secrets = [s for s in secrets if s]

    def filter(self, record):
        msg = record.getMessage()
        if any(s in msg for s in self.secrets):
            for s in self.secrets:
                msg = msg.replace(s, "<redacted>")
            record.msg = msg
            record.args = None
        return True


def allowed_chat(chat_id, group_id, admin_id):
    return chat_id is not None and chat_id in (group_id, admin_id)


def is_admin(user_id, admin_id):
    return user_id is not None and user_id == admin_id


def card_state(in_library, has_files, kept, seerr_status=None):
    if in_library and kept:
        return STATE_KEPT
    if in_library and has_files:
        return STATE_ON_DISK
    if in_library or seerr_status in (SEERR_PENDING, SEERR_PROCESSING):
        return STATE_DOWNLOADING
    return STATE_MISSING


def card_actions(state, admin):
    if state == STATE_MISSING:
        return ["keep", "request"] if admin else ["request"]
    if state in (STATE_DOWNLOADING, STATE_ON_DISK):
        return ["keep"] if admin else []
    if state == STATE_KEPT:
        return ["unkeep"] if admin else []
    return []


def _parse_date(value):
    if not value:
        return None
    if isinstance(value, (int, float)):
        return dt.datetime.fromtimestamp(value / 1000 if value > 1e11 else value, dt.timezone.utc).date()
    try:
        return dt.datetime.fromisoformat(str(value).replace("Z", "+00:00")).date()
    except ValueError:
        try:
            return dt.date.fromisoformat(str(value)[:10])
        except ValueError:
            return None


def _media_type(collection_type):
    t = str(collection_type).lower()
    return "movie" if t in ("movie", "1") else "tv"


def parse_maintainerr(collections, media_by_collection=None):
    media_by_collection = media_by_collection or {}
    out = []
    for c in collections or []:
        if not isinstance(c, dict) or c.get("isActive") is False:
            continue
        days = c.get("deleteAfterDays")
        if not isinstance(days, int) or days < 0:
            continue
        media = media_by_collection.get(c.get("id"))
        if media is None:
            media = c.get("media") or []
        if isinstance(media, dict):
            media = media.get("items") or []
        mtype = _media_type(c.get("type", "movie"))
        for m in media:
            if not isinstance(m, dict):
                continue
            added = _parse_date(m.get("addDate"))
            if added is None or not (m.get("tmdbId") or m.get("tvdbId")):
                continue
            out.append(
                {
                    "type": mtype,
                    "tmdbId": m.get("tmdbId"),
                    "tvdbId": m.get("tvdbId"),
                    "due": added + dt.timedelta(days=days),
                    "collection": c.get("title", ""),
                }
            )
    return out


def due_within(items, today, days):
    soonest = {}
    for it in items:
        if (it["due"] - today).days > days:
            continue
        key = (it["type"], it["tmdbId"], it["tvdbId"])
        if key not in soonest or it["due"] < soonest[key]["due"]:
            soonest[key] = it
    return sorted(soonest.values(), key=lambda i: i["due"])


def leaving_index(items):
    idx = {}
    for it in items:
        for kind in ("tmdbId", "tvdbId"):
            if it.get(kind):
                key = (it["type"], kind[:4], int(it[kind]))
                if key not in idx or it["due"] < idx[key]:
                    idx[key] = it["due"]
    return idx


def encode_cb(origin, action, mtype, kind, ident):
    return "|".join([origin, action, mtype, kind, str(ident)])


def decode_cb(data):
    parts = (data or "").split("|")
    if len(parts) != 5 or not parts[4].isdigit():
        return None
    origin, action, mtype, kind, ident = parts
    if action not in ("keep", "unkeep", "request") or mtype not in ("movie", "tv") or kind not in ("tmdb", "tvdb"):
        return None
    return origin, action, mtype, kind, int(ident)


def chunk_lines(lines, limit=TG_TEXT_LIMIT, max_lines=None):
    chunks, cur, size = [], [], 0
    for line in lines:
        if len(line) > limit:
            line = line[: limit - 1] + "…"
        if cur and (size + 1 + len(line) > limit or (max_lines and len(cur) >= max_lines)):
            chunks.append(cur)
            cur, size = [], 0
        size += len(line) + (1 if cur else 0)
        cur.append(line)
    if cur:
        chunks.append(cur)
    return chunks


def split_with_header(header, lines, limit=TG_TEXT_LIMIT, max_lines=TG_BUTTONS_PER_MESSAGE):
    out, start = [], 0
    for i, chunk in enumerate(chunk_lines(lines, limit - len(header) - 1, max_lines)):
        out.append(("\n".join(([header] if i == 0 else []) + chunk), start, start + len(chunk)))
        start += len(chunk)
    return out


def human_bytes(n):
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if n < 1024 or unit == "TiB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} B"
        n /= 1024


def progress(records):
    size = sum(r.get("size") or 0 for r in records)
    left = sum(r.get("sizeleft") or 0 for r in records)
    if not size:
        return None
    return int(round(100 * (1 - left / size)))


class Api:
    def __init__(self, name, base, key=None, header="X-Api-Key", dry_run=False):
        self.name = name
        self.base = base.rstrip("/")
        self.key = key
        self.header = header
        self.dry_run = dry_run

    def _call(self, method, path, body=None):
        headers = {"Accept": "application/json"}
        if self.key:
            headers[self.header] = self.key
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(self.base + path, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                raw = r.read()
        except urllib.error.HTTPError as e:
            log.warning("%s %s %s -> HTTP %s", self.name, method, path.split("?")[0], e.code)
            raise
        except (urllib.error.URLError, OSError, TimeoutError) as e:
            log.warning("%s %s %s unreachable: %s", self.name, method, path.split("?")[0], type(e).__name__)
            raise Unreachable(self.name) from None
        return json.loads(raw) if raw else None

    async def get(self, path):
        return await asyncio.to_thread(self._call, "GET", path)

    async def write(self, method, path, body=None):
        if self.dry_run:
            log.info("DRY-RUN %s %s %s %s", self.name, method, path, json.dumps(body))
            return None
        return await asyncio.to_thread(self._call, method, path, body)


class Arr:
    def __init__(self, api, kind, keep_tag, keep_profile):
        self.api = api
        self.kind = kind
        self.keep_tag = keep_tag
        self.keep_profile = keep_profile
        self._tag_id = None

    @property
    def items_path(self):
        return "/movie" if self.kind == "movie" else "/series"

    async def tag_id(self):
        if self._tag_id is None:
            for t in await self.api.get("/tag") or []:
                if str(t.get("label", "")).lower() == self.keep_tag:
                    self._tag_id = t["id"]
        return self._tag_id

    async def profile_id(self):
        for p in await self.api.get("/qualityprofile") or []:
            if p.get("name") == self.keep_profile:
                return p["id"]
        return None

    async def find(self, kind, ident):
        if self.kind == "movie":
            res = await self.api.get(f"/movie?tmdbId={ident}")
        elif kind == "tvdb":
            res = await self.api.get(f"/series?tvdbId={ident}")
        else:
            res = [s for s in await self.api.get("/series") or [] if s.get("tmdbId") == ident]
        return res[0] if res else None

    def has_files(self, item):
        if self.kind == "movie":
            return bool(item.get("hasFile"))
        return (item.get("statistics") or {}).get("episodeFileCount", 0) > 0

    async def queue_progress(self, item):
        key = "movieId" if self.kind == "movie" else "seriesId"
        recs = await self.api.get(f"/queue/details?{key}={item['id']}") or []
        return progress(recs)

    async def set_keep(self, item, add):
        tag = await self.tag_id()
        ids_key = "movieIds" if self.kind == "movie" else "seriesIds"
        body = {ids_key: [item["id"]], "tags": [tag], "applyTags": "add" if add else "remove"}
        if add:
            body["monitored"] = True
        await self.api.write("PUT", self.items_path + "/editor", body)
        if add:
            cmd = (
                {"name": "MoviesSearch", "movieIds": [item["id"]]}
                if self.kind == "movie"
                else {"name": "SeriesSearch", "seriesId": item["id"]}
            )
            await self.api.write("POST", "/command", cmd)

    async def all_kept(self):
        tag = await self.tag_id()
        if tag is None:
            return []
        return [i for i in await self.api.get(self.items_path) or [] if tag in (i.get("tags") or [])]


class Bot:
    def __init__(self, args, creds):
        self.args = args
        self.group_id = int(creds["group-chat-id"])
        self.admin_id = int(creds["admin-user-id"])
        dry = args.dry_run
        self.seerr = Api("Seerr", args.seerr + "/api/v1", creds["seerr-key"], dry_run=dry)
        self.maintainerr = Api("Maintainerr", args.maintainerr + "/api", dry_run=dry)
        self.arr = {
            "movie": Arr(Api("Radarr", args.radarr + "/api/v3", creds["radarr-key"], dry_run=dry), "movie", args.keep_tag, args.radarr_keep_profile),
            "tv": Arr(Api("Sonarr", args.sonarr + "/api/v3", creds["sonarr-key"], dry_run=dry), "tv", args.keep_tag, args.sonarr_keep_profile),
        }

    async def leaving(self):
        collections = await self.maintainerr.get("/collections") or []
        media = {}
        for c in collections:
            if isinstance(c, dict) and c.get("isActive", True) and c.get("deleteAfterDays") is not None and "id" in c:
                try:
                    media[c["id"]] = await self.maintainerr.get(f"/collections/media/?collectionId={c['id']}")
                except urllib.error.HTTPError:
                    pass
        return parse_maintainerr(collections, media)

    async def resolve_ids(self, mtype, kind, ident):
        if mtype == "tv" and kind == "tmdb":
            try:
                info = await self.seerr.get(f"/tv/{ident}")
                tvdb = (info.get("externalIds") or {}).get("tvdbId")
                if tvdb:
                    return "tvdb", int(tvdb), ident
            except urllib.error.HTTPError:
                pass
        return kind, ident, ident if kind == "tmdb" else None

    async def card(self, mtype, kind, ident, admin, title=None, seerr_status=None, leaving_idx=None):
        arr = self.arr[mtype]
        lines = []
        try:
            item = await arr.find(kind, ident)
        except Unreachable as e:
            return (title or f"{mtype} {ident}") + f"\n{e.app} unreachable", []
        kept = False
        if item:
            title = title or item.get("title")
            kept = (await arr.tag_id()) in (item.get("tags") or [])
        state = card_state(bool(item), bool(item) and arr.has_files(item), kept, seerr_status)
        if state == STATE_KEPT:
            lines.append("Kept")
        elif state == STATE_MISSING:
            lines.append("Not in library")
        elif state == STATE_DOWNLOADING:
            pct = None
            if item:
                try:
                    pct = await arr.queue_progress(item)
                except (Unreachable, urllib.error.HTTPError):
                    pct = None
            lines.append(f"Downloading {pct}%" if pct is not None else "Requested")
        else:
            lines.append("On disk")
        if state in (STATE_ON_DISK, STATE_DOWNLOADING) and leaving_idx is not None and item:
            due = None
            for k, v in ((kind, ident), ("tmdb", item.get("tmdbId")), ("tvdb", item.get("tvdbId"))):
                if v and (mtype, k, int(v)) in leaving_idx:
                    due = leaving_idx[(mtype, k, int(v))]
            if due:
                lines.append(f"Leaving {due.isoformat()}")
        if leaving_idx is None and state in (STATE_ON_DISK, STATE_DOWNLOADING):
            lines.append("Maintainerr unreachable")
        year = f" ({item['year']})" if item and item.get("year") else ""
        head = f"{title or ident}{year} · {'Movie' if mtype == 'movie' else 'TV'}"
        return head + "\n" + "\n".join(lines), card_actions(state, admin)

    async def do_keep(self, mtype, kind, ident, add):
        arr = self.arr[mtype]
        if await arr.tag_id() is None:
            return f"No '{self.args.keep_tag}' tag in {arr.api.name}"
        kind2, ident2, tmdb = await self.resolve_ids(mtype, kind, ident)
        item = await arr.find(kind2, ident2)
        if item:
            tagged = (await arr.tag_id()) in (item.get("tags") or [])
            if add and tagged:
                return f"{item['title']}: already kept"
            if not add and not tagged:
                return f"{item['title']}: not kept"
            await arr.set_keep(item, add)
            return ("DRY-RUN: " if self.args.dry_run else "") + f"{item['title']}: {'kept' if add else 'unkept'}"
        if not add:
            return "Not in library"
        if tmdb is None:
            return "Not in library and no TMDB id to request"
        body = {"mediaType": mtype, "mediaId": tmdb, "tags": [await arr.tag_id()]}
        profile = await arr.profile_id()
        if profile is not None:
            body["profileId"] = profile
        if mtype == "tv":
            body["seasons"] = "all"
        return await self.seerr_request(body, "requested with keep")

    async def do_request(self, mtype, tmdb):
        body = {"mediaType": mtype, "mediaId": tmdb}
        if mtype == "tv":
            body["seasons"] = "all"
        return await self.seerr_request(body, "requested")

    async def seerr_request(self, body, done):
        try:
            await self.seerr.write("POST", "/request", body)
        except urllib.error.HTTPError as e:
            if e.code == 409:
                return "Already requested"
            return f"Seerr refused the request (HTTP {e.code})"
        return ("DRY-RUN: " if self.args.dry_run else "") + done


def ptb_app(bot, token):
    from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
    from telegram.ext import (
        ApplicationBuilder,
        ApplicationHandlerStop,
        CallbackQueryHandler,
        CommandHandler,
        TypeHandler,
    )

    labels = {"keep": "Keep", "unkeep": "Unkeep", "request": "Request"}

    def markup(origin, mtype, kind, ident, actions):
        if not actions:
            return None
        return InlineKeyboardMarkup(
            [[InlineKeyboardButton(labels[a], callback_data=encode_cb(origin, a, mtype, kind, ident)) for a in actions]]
        )

    def leaving_markup(items, titles):
        rows = []
        for it in items:
            kind, ident = ("tmdb", it["tmdbId"]) if it["type"] == "movie" or not it["tvdbId"] else ("tvdb", it["tvdbId"])
            rows.append([InlineKeyboardButton(f"Keep {titles[id(it)]}"[:60], callback_data=encode_cb("l", "keep", it["type"], kind, ident))])
        return InlineKeyboardMarkup(rows) if rows else None

    async def gate(update, context):
        chat = update.effective_chat
        if not allowed_chat(chat.id if chat else None, bot.group_id, bot.admin_id):
            log.info("dropped update from chat %s", chat.id if chat else None)
            raise ApplicationHandlerStop

    async def reply(update, text, markup_=None):
        await update.effective_message.reply_text(text, reply_markup=markup_, disable_web_page_preview=True)

    async def reply_lines(update, lines):
        for chunk in chunk_lines(lines):
            await reply(update, "\n".join(chunk))

    async def cmd_search(update, context):
        query = " ".join(context.args or []).strip()
        if not query:
            await reply(update, "Usage: /s <title>")
            return
        try:
            res = await bot.seerr.get("/search?query=" + urllib.parse.quote(query, safe="") + "&page=1")
        except (Unreachable, urllib.error.HTTPError):
            await reply(update, "Seerr unreachable")
            return
        results = [r for r in (res or {}).get("results", []) if r.get("mediaType") in ("movie", "tv")][:5]
        if not results:
            await reply(update, "No results")
            return
        try:
            idx = leaving_index(await bot.leaving())
        except (Unreachable, urllib.error.HTTPError, ValueError):
            idx = None
        admin = is_admin(update.effective_user.id if update.effective_user else None, bot.admin_id)
        origin = "ca" if admin else "cf"
        for r in results:
            mtype = r["mediaType"]
            info = r.get("mediaInfo") or {}
            title = r.get("title") or r.get("name")
            year = (r.get("releaseDate") or r.get("firstAirDate") or "")[:4]
            label = f"{title} ({year})" if year else title
            kind, ident = "tmdb", r["id"]
            if mtype == "tv" and info.get("tvdbId"):
                kind, ident = "tvdb", int(info["tvdbId"])
            elif mtype == "tv":
                try:
                    kind, ident, _ = await bot.resolve_ids(mtype, "tmdb", r["id"])
                except Unreachable:
                    pass
            text, actions = await bot.card(mtype, kind, ident, admin, label, info.get("status"), idx)
            await reply(update, text, markup(origin, mtype, "tmdb", r["id"], actions))

    async def cmd_queue(update, context):
        lines = []
        for mtype, arr in bot.arr.items():
            inc = "includeMovie=true" if mtype == "movie" else "includeSeries=true&includeEpisode=true"
            try:
                recs = (await arr.api.get(f"/queue?pageSize=50&{inc}") or {}).get("records", [])
            except (Unreachable, urllib.error.HTTPError):
                lines.append(f"{arr.api.name} unreachable")
                continue
            lines.append(f"{arr.api.name}: {len(recs)} in queue")
            for r in recs[:15]:
                name = ((r.get("movie") or r.get("series") or {}).get("title")) or r.get("title", "?")
                ep = r.get("episode") or {}
                if ep:
                    name += f" S{ep.get('seasonNumber', 0):02d}E{ep.get('episodeNumber', 0):02d}"
                pct = progress([r])
                lines.append(f"  {name} {pct if pct is not None else '?'}% {r.get('timeleft') or ''}".rstrip())
        await reply_lines(update, lines)

    async def cmd_disk(update, context):
        try:
            st = os.statvfs(bot.args.media_root)
        except OSError:
            await reply(update, "Media disk unreadable")
            return
        free = st.f_bavail * st.f_frsize
        total = st.f_blocks * st.f_frsize
        await reply(update, f"Media disk: {human_bytes(free)} free of {human_bytes(total)}")

    async def titled(items):
        titles = {}
        for it in items:
            kind, ident = ("tmdb", it["tmdbId"]) if it["type"] == "movie" or not it["tvdbId"] else ("tvdb", it["tvdbId"])
            name = None
            try:
                item = await bot.arr[it["type"]].find(kind, ident)
                name = item.get("title") if item else None
            except (Unreachable, urllib.error.HTTPError):
                pass
            titles[id(it)] = name or f"{it['type']} {ident}"
        return titles

    async def leaving_message(days):
        items = due_within(await bot.leaving(), dt.date.today(), days)
        if not items:
            return []
        titles = await titled(items)
        header = f"Leaving within {days} days (no reply means it goes):"
        lines = [f"  {it['due'].isoformat()}  {titles[id(it)]}" for it in items]
        return [(text, leaving_markup(items[a:b], titles)) for text, a, b in split_with_header(header, lines)]

    async def cmd_leaving(update, context):
        try:
            messages = await leaving_message(bot.args.digest_days)
        except (Unreachable, urllib.error.HTTPError, ValueError):
            await reply(update, "Maintainerr unreachable")
            return
        if not messages:
            await reply(update, f"Nothing leaving within {bot.args.digest_days} days")
        for text, mk in messages:
            await reply(update, text, mk)

    async def cmd_kept(update, context):
        lines = []
        for arr in bot.arr.values():
            try:
                kept = await arr.all_kept()
            except (Unreachable, urllib.error.HTTPError):
                lines.append(f"{arr.api.name} unreachable")
                continue
            lines.append(f"{arr.api.name}: {len(kept)} kept")
            lines += [f"  {i.get('title')}" for i in sorted(kept, key=lambda i: i.get("sortTitle") or i.get("title", ""))]
        await reply_lines(update, lines)

    async def on_button(update, context):
        q = update.callback_query
        parsed = decode_cb(q.data)
        if parsed is None:
            await q.answer()
            return
        origin, action, mtype, kind, ident = parsed
        uid = q.from_user.id if q.from_user else None
        if action in ("keep", "unkeep") and not is_admin(uid, bot.admin_id):
            await q.answer("admin only", show_alert=True)
            return
        try:
            if action == "request":
                result = await bot.do_request(mtype, ident)
            else:
                result = await bot.do_keep(mtype, kind, ident, action == "keep")
        except Unreachable as e:
            await q.answer(f"{e.app} unreachable", show_alert=True)
            return
        except urllib.error.HTTPError as e:
            await q.answer(f"Failed (HTTP {e.code})", show_alert=True)
            return
        log.info("%s %s %s:%s by %s -> %s", action, mtype, kind, ident, uid, result)
        await q.answer(result[:190])
        if origin in ("ca", "cf") and q.message is not None:
            head = (q.message.text or "").split("\n", 1)[0]
            try:
                k2, i2, _ = await bot.resolve_ids(mtype, kind, ident)
                text, actions = await bot.card(mtype, k2, i2, origin == "ca", head.rsplit(" · ", 1)[0], SEERR_PENDING if action != "unkeep" else None, {})
                mk = markup(origin, mtype, kind, ident, actions)
                await q.edit_message_text(text, reply_markup=mk)
            except Exception as e:
                log.info("card refresh skipped: %s", type(e).__name__)

    async def digest(context):
        try:
            messages = await leaving_message(bot.args.digest_days)
        except (Unreachable, urllib.error.HTTPError, ValueError) as e:
            log.error("reaper digest not sent, %s unreachable", getattr(e, "app", type(e).__name__))
            return
        failed = 0
        for text, mk in messages:
            try:
                await context.bot.send_message(bot.group_id, text, reply_markup=mk)
            except Exception as e:
                failed += 1
                log.warning("digest part failed: %s", type(e).__name__)
        if failed:
            log.error("reaper digest: %d of %d parts not sent", failed, len(messages))

    async def on_error(update, context):
        log.error("handler error: %s", type(context.error).__name__)

    app = ApplicationBuilder().token(token).build()
    app.add_handler(TypeHandler(Update, gate), group=-1)
    app.add_handler(CommandHandler("s", cmd_search))
    app.add_handler(CommandHandler("queue", cmd_queue))
    app.add_handler(CommandHandler("disk", cmd_disk))
    app.add_handler(CommandHandler("leaving", cmd_leaving))
    app.add_handler(CommandHandler("kept", cmd_kept))
    app.add_handler(CallbackQueryHandler(on_button))
    app.add_error_handler(on_error)
    tz = None
    if bot.args.tz:
        from zoneinfo import ZoneInfo

        tz = ZoneInfo(bot.args.tz)
    hh, mm = (int(x) for x in bot.args.digest_time.split(":"))
    app.job_queue.run_daily(digest, dt.time(hh, mm, tzinfo=tz), name="reaper-digest")
    return app


def read_creds(names):
    base = os.environ["CREDENTIALS_DIRECTORY"]
    out = {}
    for n in names:
        with open(os.path.join(base, n)) as f:
            out[n] = f.read().strip()
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--radarr", required=True)
    p.add_argument("--sonarr", required=True)
    p.add_argument("--seerr", required=True)
    p.add_argument("--maintainerr", required=True)
    p.add_argument("--media-root", required=True)
    p.add_argument("--keep-tag", default="keep")
    p.add_argument("--radarr-keep-profile", default="UHD Bluray + WEB")
    p.add_argument("--sonarr-keep-profile", default="Ultra-HD")
    p.add_argument("--digest-days", type=int, default=3)
    p.add_argument("--digest-time", default="18:00")
    p.add_argument("--tz", default=None)
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    creds = read_creds(["telegram-token", "group-chat-id", "admin-user-id", "radarr-key", "sonarr-key", "seerr-key"])
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    redact = Redact([creds["telegram-token"], creds["radarr-key"], creds["sonarr-key"], creds["seerr-key"]])
    for h in logging.getLogger().handlers:
        h.addFilter(redact)
    for noisy in ("httpx", "httpcore", "apscheduler"):
        logging.getLogger(noisy).setLevel(logging.WARNING)

    bot = Bot(args, creds)
    app = ptb_app(bot, creds["telegram-token"])
    log.info("starting%s", " (dry-run)" if args.dry_run else "")
    app.run_polling(allowed_updates=["message", "callback_query"], drop_pending_updates=False)


if __name__ == "__main__":
    main()
