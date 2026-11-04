import datetime as dt
import importlib.util
import logging
import sys
import unittest

spec = importlib.util.spec_from_file_location("media_bot", sys.argv[1])
mb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mb)

GROUP = -1001234567890
ADMIN = 4242


class Auth(unittest.TestCase):
    def test_group_and_admin_private_chat_allowed(self):
        self.assertTrue(mb.allowed_chat(GROUP, GROUP, ADMIN))
        self.assertTrue(mb.allowed_chat(ADMIN, GROUP, ADMIN))

    def test_other_chats_dropped(self):
        self.assertFalse(mb.allowed_chat(-100999, GROUP, ADMIN))
        self.assertFalse(mb.allowed_chat(7, GROUP, ADMIN))
        self.assertFalse(mb.allowed_chat(None, GROUP, ADMIN))

    def test_admin_check(self):
        self.assertTrue(mb.is_admin(ADMIN, ADMIN))
        self.assertFalse(mb.is_admin(7, ADMIN))
        self.assertFalse(mb.is_admin(None, ADMIN))
        self.assertFalse(mb.is_admin(GROUP, ADMIN))

    def test_callback_data_round_trip_and_rejects_junk(self):
        data = mb.encode_cb("ca", "keep", "tv", "tvdb", 81189)
        self.assertLessEqual(len(data.encode()), 64)
        self.assertEqual(mb.decode_cb(data), ("ca", "keep", "tv", "tvdb", 81189))
        for bad in ["", "x", "ca|delete|movie|tmdb|1", "ca|keep|music|tmdb|1", "ca|keep|movie|imdb|1", "ca|keep|movie|tmdb|1x", None]:
            self.assertIsNone(mb.decode_cb(bad))

    def test_redact_filter_hides_tokens(self):
        f = mb.Redact(["123:SECRET", ""])
        rec = logging.LogRecord("x", logging.INFO, "", 0, "url https://api.telegram.org/bot%s/getUpdates", ("123:SECRET",), None)
        f.filter(rec)
        self.assertNotIn("SECRET", rec.getMessage())


class CardState(unittest.TestCase):
    def test_states(self):
        self.assertEqual(mb.card_state(False, False, False), mb.STATE_MISSING)
        self.assertEqual(mb.card_state(False, False, False, 5), mb.STATE_MISSING)
        self.assertEqual(mb.card_state(False, False, False, mb.SEERR_PENDING), mb.STATE_DOWNLOADING)
        self.assertEqual(mb.card_state(False, False, False, mb.SEERR_PROCESSING), mb.STATE_DOWNLOADING)
        self.assertEqual(mb.card_state(True, False, False), mb.STATE_DOWNLOADING)
        self.assertEqual(mb.card_state(True, True, False), mb.STATE_ON_DISK)
        self.assertEqual(mb.card_state(True, True, True), mb.STATE_KEPT)
        self.assertEqual(mb.card_state(True, False, True), mb.STATE_KEPT)

    def test_buttons_match_spec_table(self):
        self.assertEqual(mb.card_actions(mb.STATE_MISSING, True), ["keep", "request"])
        self.assertEqual(mb.card_actions(mb.STATE_MISSING, False), ["request"])
        self.assertEqual(mb.card_actions(mb.STATE_DOWNLOADING, True), ["keep"])
        self.assertEqual(mb.card_actions(mb.STATE_DOWNLOADING, False), [])
        self.assertEqual(mb.card_actions(mb.STATE_ON_DISK, True), ["keep"])
        self.assertEqual(mb.card_actions(mb.STATE_ON_DISK, False), [])
        self.assertEqual(mb.card_actions(mb.STATE_KEPT, True), ["unkeep"])
        self.assertEqual(mb.card_actions(mb.STATE_KEPT, False), [])

    def test_progress(self):
        self.assertEqual(mb.progress([{"size": 100, "sizeleft": 25}]), 75)
        self.assertIsNone(mb.progress([]))
        self.assertIsNone(mb.progress([{"size": 0, "sizeleft": 0}]))


class Chunking(unittest.TestCase):
    def test_lines_split_under_telegram_limit(self):
        lines = [f"  Some fairly long kept title number {i} (2024)" for i in range(600)]
        chunks = mb.chunk_lines(lines)
        self.assertGreater(len(chunks), 1)
        self.assertEqual(sum(chunks, []), lines)
        self.assertTrue(all(len("\n".join(c)) <= mb.TG_TEXT_LIMIT for c in chunks))

    def test_single_overlong_line_is_truncated(self):
        chunks = mb.chunk_lines(["x" * 5000, "y"])
        self.assertEqual(len(chunks[0][0]), mb.TG_TEXT_LIMIT)
        self.assertEqual(chunks[-1][-1], "y")
        self.assertEqual(mb.chunk_lines([]), [])

    def test_digest_split_respects_text_and_button_caps(self):
        header = "Leaving within 3 days (no reply means it goes):"
        lines = [f"  2026-11-05  Title {i} " + "z" * (i % 120) for i in range(230)]
        parts = mb.split_with_header(header, lines)
        self.assertTrue(parts[0][0].startswith(header))
        self.assertTrue(all(not p[0].startswith(header) for p in parts[1:]))
        self.assertEqual([(a, b) for _, a, b in parts], [(p[1], p[2]) for p in parts])
        self.assertEqual(parts[0][1], 0)
        self.assertEqual(parts[-1][2], len(lines))
        self.assertTrue(all(parts[i][2] == parts[i + 1][1] for i in range(len(parts) - 1)))
        self.assertTrue(all(len(t) <= mb.TG_TEXT_LIMIT and b - a <= mb.TG_BUTTONS_PER_MESSAGE for t, a, b in parts))


class Maintainerr(unittest.TestCase):
    collections = [
        {"id": 1, "title": "Old movies", "isActive": True, "deleteAfterDays": 30, "type": "movie"},
        {"id": 2, "title": "Stale shows", "isActive": True, "deleteAfterDays": 14, "type": "show"},
        {"id": 3, "title": "Off", "isActive": False, "deleteAfterDays": 1, "type": "movie"},
        {"id": 4, "title": "No delete", "isActive": True, "deleteAfterDays": None, "type": "movie"},
    ]
    media = {
        1: [
            {"id": 10, "collectionId": 1, "mediaServerId": "a", "tmdbId": 603, "addDate": "2026-10-05T00:00:00.000Z"},
            {"id": 11, "collectionId": 1, "mediaServerId": "b", "tmdbId": 604, "addDate": "2026-09-01"},
            {"id": 12, "collectionId": 1, "mediaServerId": "c", "addDate": "2026-10-05"},
        ],
        2: [{"id": 20, "collectionId": 2, "mediaServerId": "d", "tvdbId": 81189, "tmdbId": 1396, "addDate": "2026-10-22T10:00:00Z"}],
        3: [{"id": 30, "collectionId": 3, "mediaServerId": "e", "tmdbId": 1, "addDate": "2026-10-01"}],
        4: [{"id": 40, "collectionId": 4, "mediaServerId": "f", "tmdbId": 2, "addDate": "2026-10-01"}],
    }

    def test_parse(self):
        items = mb.parse_maintainerr(self.collections, self.media)
        got = sorted((i["type"], i["tmdbId"], i["due"].isoformat()) for i in items)
        self.assertEqual(got, [("movie", 603, "2026-11-04"), ("movie", 604, "2026-10-01"), ("tv", 1396, "2026-11-05")])

    def test_embedded_media_and_paged_shape(self):
        cols = [dict(self.collections[0], media=self.media[1][:1])]
        self.assertEqual(len(mb.parse_maintainerr(cols)), 1)
        self.assertEqual(len(mb.parse_maintainerr(self.collections[:1], {1: {"totalSize": 1, "items": self.media[1][:1]}})), 1)

    def test_garbage_is_ignored(self):
        self.assertEqual(mb.parse_maintainerr(None), [])
        self.assertEqual(mb.parse_maintainerr([None, "x", {"id": 9, "deleteAfterDays": "3"}]), [])
        self.assertEqual(mb.parse_maintainerr([{"id": 9, "deleteAfterDays": 3, "media": [{"tmdbId": 1, "addDate": "nope"}]}]), [])

    def test_due_within_window_and_dedup(self):
        items = mb.parse_maintainerr(self.collections, self.media)
        items.append(dict(items[0], due=items[0]["due"] + dt.timedelta(days=1)))
        due = mb.due_within(items, dt.date(2026, 11, 3), 3)
        self.assertEqual([(i["tmdbId"], i["due"].isoformat()) for i in due], [(604, "2026-10-01"), (603, "2026-11-04"), (1396, "2026-11-05")])
        self.assertEqual(mb.due_within(items, dt.date(2026, 10, 1), 3), [i for i in mb.due_within(items, dt.date(2026, 10, 1), 3) if i["tmdbId"] == 604])

    def test_leaving_index(self):
        idx = mb.leaving_index(mb.parse_maintainerr(self.collections, self.media))
        self.assertEqual(idx[("tv", "tvdb", 81189)], dt.date(2026, 11, 5))
        self.assertEqual(idx[("movie", "tmdb", 603)], dt.date(2026, 11, 4))


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]], verbosity=2)
