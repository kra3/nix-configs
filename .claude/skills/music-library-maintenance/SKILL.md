---
name: music-library-maintenance
description: Use when working on sutala's music library: Lidarr, Slskd, SABnzbd, beets databases/profiles, failed or duplicate imports, library-vs-disk consistency audits, or the lidarr-beets-webhook and lidarr-failed-import-recovery services. Holds the layout, rules, stack wiring, Lidarr quality settings, beets quirks and the audit procedure.
---

# Music library maintenance (sutala)

Goal: files on disk, beets databases and Lidarr agree, with no manual steps for ordinary downloads.

## Rules
- Never read secrets. Anything needing the Lidarr API key (`/run/secrets/media.lidarr.api_key`) is a script the user runs as `! sudo <python> script.py`.
- sutala is local, no ssh. File work goes through `sg media -c '...'` (group `media`, gid 2000). One-off scripts go in the scratchpad or `/tmp`, never the repo.
- Service fixes ship as nix changes via worktree + PR. Approved one-off work on library files is fine.
- Confirm before every delete. If the classifier blocks `rm`, give the user the exact command instead of working around it.
- No Lidarr state changes without evidence; Lidarr's Unmapped Files view deletes files for real.
- Resolve beets paths against the profile `directory` before calling a file missing.

## Session gotchas
- Git is blocked inside an EnterWorktree session: `ExitWorktree keep`, then `git -C <worktree> ...`.
- A PreToolUse hook sometimes rejects harmless Bash with a bogus "git push blocked"/"commit to main" error (long inline commands, process substitution): put the logic in a script file.
- `beet` is a shell alias adding `--config /run/secrets/rendered/music/beets-secrets.yaml`; scripts must pass it explicitly. No ffprobe/metaflac on the host: import `mediafile`/`mutagen` by adding their store paths with `site.addsitedir`.
- Never set `BEETSDIR=` empty: beets silently creates `library.db` in the cwd.

## Layout
- Library `/srv/media/library/music/{Western,Indian,Classical/{Western,Carnatic,Hindustani},Devotional,playlists}`; containers see `/data/library/music`. Devotional is not in Lidarr. Lidarr writes files as uid 0 gid 2000, mode 775.
- Downloads: `/srv/media/downloads/slskd/complete`, `/srv/media/downloads/usenet/complete/music`.
- Beets profiles (nix: `modules/home/music/beets.nix`; all dbs in `~/.config/beets/`):
  - Western: `beet` (no BEETSDIR), dir `.../music/Western`, `western.db`.
  - Indian: `beet-indian-film` (`BEETSDIR=~/.config/beets-indian-film`), dir `.../music/Indian`, `indian-film.db`, `strong_rec_thresh 0.15`.
  - Classical: `beet-classical` (`BEETSDIR=~/.config/beets-classical`), dir `.../music/Classical/Western`, `classical.db`.
  - Carnatic and Hindustani have no profile.

## Stack wiring (nix: `modules/containers/media-mgmt/`, `modules/services/media/`)
- Containers share the `br-media-mgmt` bridge (addresses in `modules/vars.nix`), PUID 1000 / PGID 2000. Behind nginx forward-auth: Lidarr, Prowlarr, SABnzbd, Slskd (its P2P port is open on the LAN firewall). No vhost: Unpackerr, Recyclarr.
- Flow: Lidarr searches a Usenet indexer (via Prowlarr), the Slskd indexer and Tubifarry (YouTube); grabs land in `/srv/media/downloads/...`; Lidarr imports into the library.
- UI-managed, not nix: Lidarr quality/metadata/naming (Recyclarr does Radarr/Sonarr only), SABnzbd unwanted extensions and encrypted RARs. Unpackerr's Lidarr target is torrent-only.
- Slskd shares Western and Indian read-only; `slskd.yml` upload `speed_limit` 25000, 3000 for leechers (<=1 shared file/dir).
- Playback: Jellyfin and Navidrome (nspawn `media-play`) mount `/srv/media`; Music Assistant uses Navidrome and feeds Snapcast. They see changes only after their own scans.
- `lidarr-beets-webhook` (host :8942, open on `br-media-mgmt` only): Lidarr's custom script forwards only `TrackRetag` events (it also logs every event to `/config/retag-debug.log`). One `beet import -q --quiet-fallback asis` per album folder, extra config `~/.config/beets-lidarr-hook/overlay.yaml` (move/copy off, write/autotag/quiet on, `permissions` disabled). `Indian/` uses the Indian profile; `Western/` and all of `Classical/` use the Western profile (so Classical rows land in `western.db` with absolute paths); other paths are ignored.
- `lidarr-failed-import-recovery` (timer, every 5 min, `dryRun` toggle in nix): for Slskd/SABnzbd queue entries in `importFailed` under the two download dirs:
  - Folder gone: clear the entry (`removeFromClient=true` for SABnzbd only).
  - Classical root folder: skipped, notify.
  - Album already in beets (by `mb_albumid`, else album + artist) with >=90% of the download's tracks: clear the entry, leave the download, notify. Under 90%: left for a manual replace import.
  - Else `beet import -q --quiet-fallback skip -S <expected MB release>` with `strong_rec_thresh 0.25`; if no audio is left, update the artist path (only if the old folder has no audio), clear the entry, `RefreshArtist`, remove empty dirs.
  - Unresolved entries are retried after 24 h; Telegram notifies once per entry. State: `/var/lib/lidarr-failed-import-recovery/tried.json`.
- Failure signs: Lidarr queue `importFailed`/`warning`; SABnzbd `_FAILED_*` folders; retag bursts in the webhook journal with high HDD I/O; Telegram messages from the recovery job.

## Lidarr settings (3.1.6, live dump 2026-10-08; re-dump before trusting)
- Quality profiles: `Any` (MP3-96 up, cutoff lossless, upgrades on), `Lossless` (no upgrades), `Standard` (lossy 192 up). All root folders default new artists to profile id 1 (`Any`), so set Lossless per artist when FLAC matters.
- Metadata profiles: `Standard` (Album, Studio, Official) for Western/Classical; `Standard - Indian` adds Soundtrack. 297 artists, 460 of 8,215 albums monitored.
- Delay profile: Usenet 0 min, Soulseek 30, YouTube 60, bypass at highest quality. Indexer priority (Usenet best, then Slskd, then Tubifarry) only breaks ties after quality; Soulseek dominates grabs because it returns many candidates.
- Release profile ignores `WALKMAN`; no custom formats. Import lists (Last.fm Recommend, three ListenBrainz) keep adding artists.
- Slskd indexer: audio only, min peer upload speed 100, track-count filter Disabled, 100 responses, 5 s timeout, one search at a time, fallback search on, track fallback off, 3 retries. Loose matching yields partial or wrong-edition sets that end in `importFailed`.
- Tubifarry: fuzzy matching, track-count tolerance 2, year tolerance 1, 20 results; YouTube client re-encodes and uses SponsorBlock.
- Naming: `{Artist Name}/{Album Title} ({Release Year})/{track:00} - {Track Title}`, multi-disc `{medium:00}-{track:00} - ...`. Beets' path format drops the disc number: compare tags, not file names.
- `copyUsingHardlinks` off: each import leaves a second copy in the download folder; empty it after a verified import. Only `.srt` extras import, so copy `.lrc` manually when replacing an album.
- Recycle bin `/srv/media/.recycle-bin` (`/data/.recycle-bin`), 30-day purge.
- Tag writing must stay "For new downloads only" (scrub off, cover art embedded). "All files; keep in sync with MusicBrainz" made Lidarr and beets rewrite each other's tags every 7-10 min, with hours of HDD reads.

## Beets quirks
- Paths are relative to the profile `directory`; items outside it are absolute. Compare via `beet ls -f '$path'`, never raw sqlite.
- `-q` skips an album whose name matches an existing one and caps matches with unmatched/missing tracks; for those the user runs an interactive import with `import: duplicate_action: merge|keep|remove` in a temp overlay.
- `beet remove -f` removes rows only; `beet move -a id:N` moves files.
- A `move: yes` import can leave stale rows for the same album in another profile's db: confirm the stale paths don't exist, then remove the rows.
- Library copy with <90% of the download's tracks is partial, not a duplicate: replace it, keep the download.
- Before deleting a "duplicate", check format (FLAC vs MP3) and match by album + track number, not title substring.

## Audit
1. Export disk audio files and beets items from all three profiles. Expect no beets rows without a file; only Devotional is untracked by Lidarr.
2. Lidarr: trackfile count and missing files, queue summary, failed imports, retag check (history `trackFileRetagged` counts and `diff`).
3. Disk files not in beets: first same-name albums under another year/folder (duplicates), then in-flight Lidarr churn (webhook running), then genuine imports.
4. Duplicate folders: compare tags and MB release id before choosing; carry `.lrc` files across by disc and track.
5. Re-run the export after any delete and report the numbers.

## Open items (2026-10-08)
- Carnatic (11) and Hindustani (1) files have no beets profile.
- Mozart *Organ Works* (9 untagged files) in `slskd/complete`.
- Classical artist folders with long multi-artist names (recovery job skips Classical).
- 5 KB `00 -.mp3` in `Classical/Western/.../Mozart_ The Works for Flute (1994)`, probably junk.
