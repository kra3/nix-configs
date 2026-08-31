{
  flake.nixosModules.services-virtualisation-podman-socket-proxy =
  { ... }:
  {
    # Sits in front of the host's rootful podman socket
    # (/run/podman/podman.sock) so Arcane and Homepage never touch it
    # directly — a compromise in either only gets what this proxy grants,
    # not host-root-equivalent control. https://github.com/Tecnativa/docker-socket-proxy
    #
    # Not packaged in nixpkgs (no native module/package exists), so this
    # runs as a rootful quadlet container like the rest of the app fleet,
    # bound to loopback only — nothing outside the host can reach it.
    virtualisation.quadlet.containers.podman-socket-proxy = {
      containerConfig = {
        image = "ghcr.io/tecnativa/docker-socket-proxy:v0.5.0";
        publishPorts = [ "127.0.0.1:2375:2375" ];
        volumes = [
          "/run/podman/podman.sock:/var/run/docker.sock:ro"
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
