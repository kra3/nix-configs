{
  flake.nixosModules.services-media-lidarr-beets-webhook =
    { pkgs, ... }:
    let
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

      script = pkgs.writeText "lidarr-beets-webhook.py" ''
        import http.server
        import os
        import queue
        import subprocess
        import threading

        PORT = ${toString port}
        HOST_ROOT = "${hostMusicRoot}"
        CONTAINER_ROOT = "${containerMusicRoot}"
        BEETS_BASE = "${beetsBase}"
        OVERLAY = "${overlay}"

        # Retag events can arrive in bursts (e.g. a bulk library refresh) much
        # faster than `beet import` can process them one at a time; queuing
        # keeps do_POST fast so wget doesn't time out waiting its turn.
        work_queue = queue.Queue()

        def worker():
            while True:
                album_dir, env = work_queue.get()
                # No TTY here, so an ambiguous match's prompt would otherwise hit
                # closed stdin and get silently skipped (exit 0, nothing imported).
                result = subprocess.run(
                    ["beet", "--config", BEETS_BASE, "--config", OVERLAY, "import", "-q", "--quiet-fallback", "asis", album_dir],
                    env=env, capture_output=True, text=True,
                )
                if result.returncode != 0:
                    print(album_dir, result.stdout, result.stderr)

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                length = int(self.headers.get("Content-Length", 0))
                track_path = self.rfile.read(length).decode()

                if not track_path.startswith(CONTAINER_ROOT):
                    self.send_response(400)
                    self.end_headers()
                    return

                host_path = HOST_ROOT + track_path[len(CONTAINER_ROOT):]
                album_dir = os.path.dirname(host_path)

                if host_path.startswith(HOST_ROOT + "/Indian/"):
                    env = dict(os.environ, BEETSDIR="/home/kra3/.config/beets-indian-film")
                elif host_path.startswith(HOST_ROOT + "/Western/") or host_path.startswith(HOST_ROOT + "/Classical/"):
                    env = dict(os.environ)
                else:
                    self.send_response(204)
                    self.end_headers()
                    return

                work_queue.put((album_dir, env))
                self.send_response(202)
                self.end_headers()

            def log_message(self, fmt, *args):
                print(fmt % args)

        threading.Thread(target=worker, daemon=True).start()
        http.server.HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
      '';
    in
    {
      systemd.services.lidarr-beets-webhook = {
        description = "Bridges Lidarr's On Track Retag hook to the host's beet install";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.python3}/bin/python3 ${script}";
          User = "kra3";
          Environment = "PATH=/etc/profiles/per-user/kra3/bin:/run/current-system/sw/bin";
          Restart = "on-failure";
        };
      };

      networking.firewall.interfaces.br-media-mgmt.allowedTCPPorts = [ port ];
    };
}
