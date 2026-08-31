{
  flake.nixosModules.services-virtualisation-podman-socket-proxy =
  { pkgs, ... }:
  let
    # Upstream's haproxy.cfg with one change: two explicit `bind` lines
    # instead of the templated single one, so Homepage (TCP, loopback) and
    # Arcane (Unix socket, permission-scoped) get independently-scoped
    # access instead of sharing one bind's parameters. See the file's own
    # comment for why this can't be done via env vars alone.
    haproxyConfig = pkgs.writeText "podman-socket-proxy-haproxy.cfg" (
      builtins.readFile ./podman-socket-proxy-haproxy.cfg
    );
  in
  {
    # Sits in front of the host's rootful podman socket
    # (/run/podman/podman.sock) so Arcane and Homepage never touch it
    # directly — a compromise in either only gets what this proxy grants,
    # not host-root-equivalent control. https://github.com/Tecnativa/docker-socket-proxy
    #
    # Not packaged in nixpkgs (no native module/package exists), so this
    # runs as a rootful quadlet container like the rest of the app fleet.
    # Homepage reaches it over loopback TCP (native host process, no
    # network boundary to cross). Arcane reaches it over a Unix socket
    # instead — Arcane runs inside its own rootless-podman network
    # namespace (modules/users/arcane.nix), which by design can't reach
    # the host's other loopback-bound services (Prometheus, Alloy,
    # Homepage's own unauthenticated backend port, etc.); routing it over
    # TCP would mean opting the whole namespace into reaching all of
    # those just to reach this one proxy. The socket is owned root:arcane
    # mode 660, so nothing outside the arcane uid/gid can open it either.
    systemd.tmpfiles.rules = [
      "d /run/podman-socket-proxy 0755 root root - -"
    ];
    virtualisation.quadlet.containers.podman-socket-proxy = {
      containerConfig = {
        image = "ghcr.io/tecnativa/docker-socket-proxy:v0.5.0";
        publishPorts = [ "127.0.0.1:2375:2375" ];
        volumes = [
          "/run/podman/podman.sock:/var/run/docker.sock:ro"
          "/run/podman-socket-proxy:/run/podman-socket-proxy"
          "${haproxyConfig}:/usr/local/etc/haproxy/haproxy.cfg.template:ro"
        ];
        environments = {
          # Arcane's documented "essential for operation" set — full
          # container/image/network/volume management including EXEC.
          # AUTH/SECRETS stay off; nothing here can read sops secrets.
          EVENTS = "1";
          PING = "1";
          VERSION = "1";
          INFO = "1";
          CONTAINERS = "1";
          EXEC = "1";
          IMAGES = "1";
          NETWORKS = "1";
          VOLUMES = "1";
          POST = "1";
          DISTRIBUTION = "1";
          AUTH = "0";
          SECRETS = "0";
        };
      };
    };
  };
}
