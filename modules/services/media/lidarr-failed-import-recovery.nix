{
  flake.nixosModules.services-media-lidarr-failed-import-recovery =
    { config, pkgs, ... }:
    let
      dryRun = false;
      lidarrUrl = "http://${config.vars.network.podmanAddresses.lidarr}:8686/api/v1";
      hostRoot = "/srv/media";
      containerRoot = "/data";
      completeDir = "${hostRoot}/downloads/slskd/complete";
      beetsBase = "/run/secrets/rendered/music/beets-secrets.yaml";
      beetsIndianDir = "/home/kra3/.config/beets-indian-film";
      indianLibrary = "${hostRoot}/library/music/Indian";
      matchOverlay = pkgs.writeText "lidarr-recovery-match.yaml" ''
        match:
          strong_rec_thresh: 0.25
      '';

      script = pkgs.writeText "lidarr-failed-import-recovery.py" ''
        import json
        import os
        import subprocess
        import time
        import urllib.error
        import urllib.parse
        import urllib.request

        DRY_RUN = ${if dryRun then "True" else "False"}
        LIDARR = "${lidarrUrl}"
        HOST_ROOT = "${hostRoot}"
        CONTAINER_ROOT = "${containerRoot}"
        COMPLETE = "${completeDir}"
        BEETS_BASE = "${beetsBase}"
        MATCH_OVERLAY = "${matchOverlay}"
        BEETS_INDIAN_DIR = "${beetsIndianDir}"
        INDIAN_LIBRARY = "${indianLibrary}"
        AUDIO = (".flac", ".mp3", ".ogg", ".m4a", ".aac", ".opus", ".wav", ".wma", ".ape", ".wv")
        STATE = os.path.join(os.environ["STATE_DIRECTORY"], "tried.json")
        RETRY_AFTER = 24 * 3600


        def cred(name):
            with open(os.path.join(os.environ["CREDENTIALS_DIRECTORY"], name)) as f:
                return f.read().strip()


        LIDARR_KEY = cred("lidarr-key")


        def api(method, path, body=None):
            req = urllib.request.Request(
                LIDARR + path,
                method=method,
                data=json.dumps(body).encode() if body is not None else None,
                headers={"X-Api-Key": LIDARR_KEY, "Content-Type": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=30) as r:
                raw = r.read()
                return json.loads(raw) if raw else None


        def notify(text):
            if DRY_RUN:
                return
            data = urllib.parse.urlencode({"chat_id": cred("telegram-chat-id"), "text": text}).encode()
            url = "https://api.telegram.org/bot" + cred("telegram-bot-token") + "/sendMessage"
            try:
                urllib.request.urlopen(urllib.request.Request(url, data=data), timeout=15)
            except Exception as e:
                print("telegram notify failed:", type(e).__name__)


        def load_tried():
            try:
                with open(STATE) as f:
                    return json.load(f)
            except FileNotFoundError:
                return {}


        def save_tried(tried):
            with open(STATE, "w") as f:
                json.dump(tried, f)


        def reason_of(q):
            msgs = [m for s in q.get("statusMessages", []) for m in s.get("messages", [])] or [
                s.get("title", "") for s in q.get("statusMessages", [])
            ]
            return (msgs[0] if msgs else "no reason given")[:140]


        def audio_left(folder):
            for _, _, files in os.walk(folder):
                if any(n.lower().endswith(AUDIO) for n in files):
                    return True
            return False


        def expected_release(q):
            try:
                album = api("GET", "/album/" + str(q["albumId"]))
            except (KeyError, urllib.error.HTTPError):
                return None, None
            rels = album.get("releases", [])
            sel = next((r for r in rels if r.get("monitored")), rels[0] if rels else None)
            return (sel["foreignReleaseId"] if sel else None), album.get("title")


        def beets_lookup(query, env):
            out = subprocess.run(
                ["beet", "--config", BEETS_BASE, "ls", "-f", "$path"] + query,
                env=env, capture_output=True, text=True,
            ).stdout.splitlines()
            return (os.path.dirname(os.path.dirname(out[0])) if out else None), len(out)


        def beets_artist_dir(query, env):
            return beets_lookup(query, env)[0]


        def audio_count(folder):
            return sum(n.lower().endswith(AUDIO) for _, _, files in os.walk(folder) for n in files)


        def reconcile(q, artist, new_dir, title):
            cur = artist["path"].rstrip("/")
            if new_dir and new_dir.startswith(HOST_ROOT + "/") and CONTAINER_ROOT + new_dir[len(HOST_ROOT):] != cur:
                old_host = HOST_ROOT + cur[len(CONTAINER_ROOT):]
                if os.path.isdir(old_host) and audio_left(old_host):
                    notify("Lidarr artist folder differs from where beets filed it, left as is: " + title)
                else:
                    full = api("GET", "/artist/" + str(artist["id"]))
                    full["path"] = CONTAINER_ROOT + new_dir[len(HOST_ROOT):]
                    api("PUT", "/artist/" + str(artist["id"]) + "?moveFiles=false", full)
            api("DELETE", "/queue/" + str(q["id"]) + "?removeFromClient=false&blocklist=false")
            api("POST", "/command", {"name": "RefreshArtist", "artistId": artist["id"]})


        def library_for(artist):
            root = os.path.basename(artist["rootFolderPath"].rstrip("/"))
            if root == "Classical":
                return None
            if root == "Indian" or os.path.isdir(os.path.join(INDIAN_LIBRARY, os.path.basename(artist["path"].rstrip("/")))):
                return "indian"
            return "western"


        tried = load_tried()
        queue = api("GET", "/queue?pageSize=500")["records"]
        failed = [q for q in queue if q.get("trackedDownloadState") == "importFailed" and q.get("downloadClient") == "Slskd"]
        print(("DRY-RUN: " if DRY_RUN else "") + str(len(failed)) + " failed Slskd imports")

        for q in failed:
            title = q["title"]
            qid = q["id"]
            folder = HOST_ROOT + q["outputPath"][len(CONTAINER_ROOT):] if q.get("outputPath", "").startswith(CONTAINER_ROOT) else ""
            if not folder.startswith(COMPLETE + "/"):
                print("SKIP out of scope:", title)
                continue
            if not os.path.isdir(folder):
                print(("WOULD " if DRY_RUN else "") + "CLEAR queue entry, download folder is gone:", title)
                if not DRY_RUN:
                    api("DELETE", "/queue/" + str(qid) + "?removeFromClient=false&blocklist=false")
                continue
            last = tried.get(str(qid))
            recent = bool(last) and time.time() - last < RETRY_AFTER
            artist = api("GET", "/artist/" + str(q["artistId"]))
            lib = library_for(artist)
            why = "Lidarr: " + reason_of(q)
            if lib is None:
                reason = "Classical artist, needs manual import | " + why
            elif (rel := expected_release(q))[0] is None:
                reason = "Lidarr no longer has the expected album | " + why
            else:
                release, album_title = rel
                env = dict(os.environ, BEETSDIR=BEETS_INDIAN_DIR) if lib == "indian" else dict(os.environ)
                have, have_n = beets_lookup(["mb_albumid:" + release], env)
                if not have:
                    have, have_n = beets_lookup(["album:" + album_title, "albumartist:" + artist["artistName"].split()[0]], env)
                if have and have_n < 0.9 * audio_count(folder):
                    reason = "library holds only " + str(have_n) + " of " + str(audio_count(folder)) + " tracks, needs a replace import | " + why
                    if recent:
                        print("SKIP tried recently:", title)
                        continue
                    print("LEFT", title, "|", reason)
                    if not DRY_RUN:
                        tried[str(qid)] = time.time()
                        save_tried(tried)
                        if last is None:
                            notify("Lidarr import failed, not auto-resolved: " + title + " (" + reason + ")")
                    continue
                if have:
                    print(("WOULD " if DRY_RUN else "") + "DUPLICATE already in beets library:", title)
                    if DRY_RUN:
                        continue
                    reconcile(q, artist, have, title)
                    tried.pop(str(qid), None)
                    save_tried(tried)
                    notify("Lidarr re-grabbed an album already in the library; queue entry cleared, download left in " + folder + ": " + title)
                    continue
                if recent:
                    print("SKIP tried recently:", title)
                    continue
                cmd = ["beet", "--config", BEETS_BASE, "--config", MATCH_OVERLAY, "import", "-q", "--quiet-fallback", "skip", "-S", release, folder]
                print(("WOULD RUN [" if DRY_RUN else "RUN [") + lib + "] " + " ".join(cmd) + " | " + title + " | " + why)
                if DRY_RUN:
                    continue
                subprocess.run(cmd, env=env, capture_output=True, text=True)
                if not audio_left(folder):
                    reconcile(q, artist, beets_artist_dir(["mb_albumid:" + release], env), title)
                    for d, _, _ in sorted(os.walk(folder), reverse=True):
                        try:
                            os.rmdir(d)
                        except OSError:
                            pass
                    tried.pop(str(qid), None)
                    save_tried(tried)
                    print("IMPORTED", title)
                    continue
                reason = "beets could not match confidently | " + why
            if recent:
                print("SKIP tried recently:", title)
                continue
            print("LEFT", title, "|", reason)
            if not DRY_RUN:
                tried[str(qid)] = time.time()
                save_tried(tried)
                if last is None:
                    notify("Lidarr import failed, not auto-resolved: " + title + " (" + reason + ")")
      '';
    in
    {
      systemd.services.lidarr-failed-import-recovery = {
        description = "Run beets over Slskd downloads Lidarr failed to import, then have Lidarr rescan";
        after = [ "lidarr.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = "kra3";
          StateDirectory = "lidarr-failed-import-recovery";
          Environment = "PATH=/etc/profiles/per-user/kra3/bin:/run/current-system/sw/bin";
          LoadCredential = [
            "lidarr-key:${config.sops.secrets."media.lidarr.api_key".path}"
            "telegram-bot-token:${config.sops.secrets."monitoring.grafana.telegram_bot_token".path}"
            "telegram-chat-id:${config.sops.secrets."monitoring.grafana.telegram_chat_id".path}"
          ];
          ExecStart = "${pkgs.python3}/bin/python3 ${script}";
        };
      };

      systemd.timers.lidarr-failed-import-recovery = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5min";
          OnUnitActiveSec = "5min";
        };
      };
    };
}
