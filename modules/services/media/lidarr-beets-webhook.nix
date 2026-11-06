{
  flake.nixosModules.services-media-lidarr-beets-webhook =
    {
      config,
      lib,
      pkgs,
      flakeLib,
      ...
    }:
    let
      cfg = config.services.lidarrBeetsWebhook;
      # Lidarr runs in a podman container and can't see the host's beet
      # binary/config/secrets; this webhook bridges that gap instead of
      # bind-mounting the nix store and secrets into a media-acquisition
      # container. Lidarr's own On Track Retag Custom Script just curls in
      # with the container-side path; this does the real path translation
      # (container /data -> host /srv/media/library/music) + beet invoke.
      port = 8942;
      beetsBase = "/run/secrets/rendered/music/beets-secrets.yaml";
      overlay = "/home/kra3/.config/beets-lidarr-hook/overlay.yaml";
      hostMusicRoot = "/srv/media/library/music";
      containerMusicRoot = "/data/library/music";
      # Host-side gateway IP of br-media-mgmt (hardcoded as 10.3.1.1 elsewhere too; no vars.nix attribute).
      bindAddr = "10.3.1.1";

      script = pkgs.writeText "lidarr-beets-webhook.py" ''
        import base64
        import hmac
        import http.server
        import os
        import queue
        import socket
        import subprocess
        import threading

        PORT = ${toString port}
        HOST_ROOT = "${hostMusicRoot}"
        CONTAINER_ROOT = "${containerMusicRoot}"
        BEETS_BASE = "${beetsBase}"
        OVERLAY = "${overlay}"
        BIND = "${bindAddr}"

        # Optional HTTP Basic auth: only enforced when a credentials file ("user:password") is provisioned.
        CREDS = None
        _cred_dir = os.environ.get("CREDENTIALS_DIRECTORY")
        if _cred_dir and os.path.exists(os.path.join(_cred_dir, "webhook-auth")):
            with open(os.path.join(_cred_dir, "webhook-auth")) as f:
                CREDS = f.read().strip()

        # Retag events can arrive in bursts (e.g. a bulk library refresh) much
        # faster than `beet import` can process them one at a time; queuing
        # keeps do_POST fast so wget doesn't time out waiting its turn.
        work_queue = queue.Queue()
        # One import per album folder is enough however many of its tracks were retagged.
        pending = set()
        pending_lock = threading.Lock()

        def worker():
            while True:
                album_dir, env = work_queue.get()
                with pending_lock:
                    pending.discard(album_dir)
                # No TTY here, so an ambiguous match's prompt would silently skip it.
                result = subprocess.run(
                    ["beet", "--config", BEETS_BASE, "--config", OVERLAY, "import", "-q", "--quiet-fallback", "asis", album_dir],
                    env=env, capture_output=True, text=True,
                )
                if result.returncode != 0:
                    print(album_dir, result.stdout, result.stderr)

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                if CREDS is not None:
                    given = ""
                    auth = self.headers.get("Authorization", "")
                    if auth.startswith("Basic "):
                        try:
                            given = base64.b64decode(auth[6:]).decode()
                        except Exception:
                            pass
                    if not hmac.compare_digest(given.encode(), CREDS.encode()):
                        self.send_response(401)
                        self.send_header("WWW-Authenticate", 'Basic realm="lidarr-beets-webhook"')
                        self.end_headers()
                        return

                length = int(self.headers.get("Content-Length", 0))
                track_path = os.path.normpath(self.rfile.read(length).decode())

                if track_path != CONTAINER_ROOT and not track_path.startswith(CONTAINER_ROOT + "/"):
                    self.send_response(400)
                    self.end_headers()
                    return

                host_path = os.path.realpath(HOST_ROOT + track_path[len(CONTAINER_ROOT):])
                if not host_path.startswith(HOST_ROOT + "/"):
                    self.send_response(400)
                    self.end_headers()
                    return
                album_dir = os.path.dirname(host_path)

                if host_path.startswith(HOST_ROOT + "/Indian/"):
                    env = dict(os.environ, BEETSDIR="/home/kra3/.config/beets-indian-film")
                elif host_path.startswith(HOST_ROOT + "/Western/") or host_path.startswith(HOST_ROOT + "/Classical/"):
                    env = dict(os.environ)
                else:
                    self.send_response(204)
                    self.end_headers()
                    return

                with pending_lock:
                    if album_dir not in pending:
                        pending.add(album_dir)
                        work_queue.put((album_dir, env))
                self.send_response(202)
                self.end_headers()

            def log_message(self, fmt, *args):
                print(fmt % args)

        threading.Thread(target=worker, daemon=True).start()

        class Server(http.server.HTTPServer):
            def server_bind(self):
                # IP_FREEBIND: the podman bridge may not exist yet at boot (netavark creates it on first container start).
                self.socket.setsockopt(socket.IPPROTO_IP, 15, 1)
                super().server_bind()

        Server((BIND, PORT), Handler).serve_forever()
      '';
    in
    {
      options.services.lidarrBeetsWebhook.credentialsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          File containing "user:password". When set, the webhook requires matching HTTP Basic auth
          (configure the same in Lidarr / the curl in its retag script). Unset keeps the open behaviour.
        '';
      };

      config = {
        systemd.services.lidarr-beets-webhook = {
          description = "Bridges Lidarr's On Track Retag hook to the host's beet install";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = lib.mkMerge [
            (flakeLib.deployment-hardening.mkServiceSandbox {
              # Music tree + beets DBs, and the per-profile BEETSDIRs where beets keeps state.pickle.
              # "-" = skip if missing.
              readWritePaths = [
                hostMusicRoot
                "/srv/appdata/media-mgmt/beets"
                "-/home/kra3/.config/beets"
                "-/home/kra3/.config/beets-indian-film"
                "-/home/kra3/.config/beets-classical"
                "-/home/kra3/.config/beets-lidarr-hook"
                "-/home/kra3/.cache/beets"
              ];
            })
            {
              ExecStart = "${pkgs.python3}/bin/python3 ${script}";
              User = "kra3";
              Environment = "PATH=/etc/profiles/per-user/kra3/bin:/run/current-system/sw/bin";
              Restart = "on-failure";
              # beets config lives in /home/kra3, so home stays visible (read-only) ...
              ProtectHome = lib.mkForce "read-only";
              # Runs as the real login user: RemoveIPC would wipe kra3's SysV/POSIX IPC (tmux,
              # browsers, /dev/shm) on every stop/restart of this unit.
              RemoveIPC = lib.mkForce false;
              # ... but this service handles input from a container, so hide the user's keys from it.
              InaccessiblePaths = [
                "-/home/kra3/.ssh"
                "-/home/kra3/.config/sops"
                "-/home/kra3/.gnupg"
              ];
            }
            (lib.mkIf (cfg.credentialsFile != null) {
              LoadCredential = [ "webhook-auth:${cfg.credentialsFile}" ];
            })
          ];
        };

        systemd.tmpfiles.rules = [ "d /srv/appdata/media-mgmt/beets 2770 kra3 media - -" ];

        networking.firewall.interfaces.br-media-mgmt.allowedTCPPorts = [ port ];
      };
    };
}
