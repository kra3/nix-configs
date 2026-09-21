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
        import subprocess
        import urllib.parse

        PORT = ${toString port}
        HOST_ROOT = "${hostMusicRoot}"
        CONTAINER_ROOT = "${containerMusicRoot}"
        BEETS_BASE = "${beetsBase}"
        OVERLAY = "${overlay}"

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(length).decode()
                params = urllib.parse.parse_qs(body)
                track_path = params.get("path", [""])[0]

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

                result = subprocess.run(
                    ["beet", "--config", BEETS_BASE, "--config", OVERLAY, "import", album_dir],
                    env=env, capture_output=True, text=True,
                )
                self.send_response(200 if result.returncode == 0 else 500)
                self.end_headers()
                if result.returncode != 0:
                    print(result.stdout, result.stderr)

            def log_message(self, fmt, *args):
                print(fmt % args)

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
