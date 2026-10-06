{
  flake.nixosModules.services-media-lidarr-failed-import-recovery =
    { config, pkgs, ... }:
    let
      dryRun = true;
      lidarrUrl = "http://${config.vars.network.podmanAddresses.lidarr}:8686/api/v1";
      hostRoot = "/srv/media";
      containerRoot = "/data";
      completeDir = "${hostRoot}/downloads/slskd/complete";
      beetsBase = "/run/secrets/rendered/music/beets-secrets.yaml";
      beetsIndianDir = "/home/kra3/.config/beets-indian-film";
      indianLibrary = "${hostRoot}/library/music/Indian";

      script = pkgs.writeText "lidarr-failed-import-recovery.py" ''
        import json
        import os
        import subprocess
        import urllib.parse
        import urllib.request

        DRY_RUN = ${if dryRun then "True" else "False"}
        LIDARR = "${lidarrUrl}"
        HOST_ROOT = "${hostRoot}"
        CONTAINER_ROOT = "${containerRoot}"
        COMPLETE = "${completeDir}"
        BEETS_BASE = "${beetsBase}"
        BEETS_INDIAN_DIR = "${beetsIndianDir}"
        INDIAN_LIBRARY = "${indianLibrary}"
        AUDIO = (".flac", ".mp3", ".ogg", ".m4a", ".aac", ".opus", ".wav", ".wma", ".ape", ".wv")
        STATE = os.path.join(os.environ["STATE_DIRECTORY"], "notified.json")


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
            urllib.request.urlopen(urllib.request.Request(url, data=data), timeout=15)


        def load_notified():
            try:
                with open(STATE) as f:
                    return set(json.load(f))
            except FileNotFoundError:
                return set()


        def audio_left(folder):
            for _, _, files in os.walk(folder):
                if any(n.lower().endswith(AUDIO) for n in files):
                    return True
            return False


        def library_for(artist):
            root = os.path.basename(artist["rootFolderPath"].rstrip("/"))
            if root == "Classical":
                return None
            if root == "Indian" or os.path.isdir(os.path.join(INDIAN_LIBRARY, os.path.basename(artist["path"].rstrip("/")))):
                return "indian"
            return "western"


        notified = load_notified()
        queue = api("GET", "/queue?pageSize=500")["records"]
        failed = [q for q in queue if q.get("trackedDownloadState") == "importFailed" and q.get("downloadClient") == "Slskd"]
        print(("DRY-RUN: " if DRY_RUN else "") + str(len(failed)) + " failed Slskd imports")

        for q in failed:
            title = q["title"]
            qid = q["id"]
            folder = HOST_ROOT + q["outputPath"][len(CONTAINER_ROOT):] if q.get("outputPath", "").startswith(CONTAINER_ROOT) else ""
            if not folder.startswith(COMPLETE + "/") or not os.path.isdir(folder):
                print("SKIP out of scope or missing folder:", title)
                continue
            artist = api("GET", "/artist/" + str(q["artistId"]))
            lib = library_for(artist)
            if lib is None:
                reason = "Classical artist, needs manual import"
            else:
                cmd = ["beet", "--config", BEETS_BASE, "import", "-q", "--quiet-fallback", "skip", folder]
                env = dict(os.environ, BEETSDIR=BEETS_INDIAN_DIR) if lib == "indian" else dict(os.environ)
                print(("WOULD RUN [" if DRY_RUN else "RUN [") + lib + "] " + " ".join(cmd) + " | " + title)
                if DRY_RUN:
                    continue
                subprocess.run(cmd, env=env, capture_output=True, text=True)
                if not audio_left(folder):
                    api("DELETE", "/queue/" + str(qid) + "?removeFromClient=false&blocklist=false")
                    api("POST", "/command", {"name": "RefreshArtist", "artistId": artist["id"]})
                    for d, _, _ in sorted(os.walk(folder), reverse=True):
                        try:
                            os.rmdir(d)
                        except OSError:
                            pass
                    print("IMPORTED", title)
                    continue
                reason = "beets could not match confidently"
            print("LEFT", title, "|", reason)
            if qid not in notified and not DRY_RUN:
                notify("Lidarr import failed, not auto-resolved: " + title + " (" + reason + ")")
                notified.add(qid)
                with open(STATE, "w") as f:
                    json.dump(sorted(notified), f)
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
