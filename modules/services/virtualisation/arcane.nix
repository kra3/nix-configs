{
  flake.nixosModules.services-virtualisation-arcane =
    {
      config,
      lib,
      inputs,
      flakeLib,
      ...
    }:
    let
      domain = config.vars.acme.domain;
      arcaneEnvPath = config.sops.templates."arcane.env".path;
    in
    {
      # Arcane itself runs under the dedicated "arcane" user's rootless podman
      # (modules/users/arcane.nix); it sees the system's rootful containers
      # only through this GET-only proxy (POST=0), so a compromise can't
      # start/stop/create anything or reach host root.
      virtualisation.quadlet.containers.arcane-socket-proxy.containerConfig = {
        image = "docker.io/tecnativa/docker-socket-proxy:v0.5.0";
        publishPorts = [ "127.0.0.1:2375:2375" ];
        volumes = [ "/run/podman/podman.sock:/var/run/docker.sock:ro" ];
        environments = {
          POST = "0";
          EVENTS = "1";
          PING = "1";
          VERSION = "1";
          INFO = "1";
          CONTAINERS = "1";
          IMAGES = "1";
          NETWORKS = "1";
          VOLUMES = "1";
        };
      };

      services.nginx.virtualHosts."oci.${domain}" = flakeLib.nginx.mkProxyVhost {
        domain = domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://127.0.0.1:3552";
        vhostExtraConfig = ''
          add_header X-Frame-Options "*";
          add_header X-Robots-Tag "noindex, nofollow";
        '';
      };

      # Traversal works despite arcane not being in "media": /srv/appdata's own mode is 0755 (media-mgmt/storage.nix).
      systemd.tmpfiles.rules = [
        "d /srv/appdata/arcane 0750 arcane arcane - -"
        "d /srv/appdata/arcane/projects 0750 arcane arcane - -"
      ];

      sops.secrets."arcane.encryption_key" = {
        owner = "arcane";
        group = "arcane";
        mode = "0400";
      };
      sops.secrets."arcane.jwt_secret" = {
        owner = "arcane";
        group = "arcane";
        mode = "0400";
      };
      sops.secrets."arcane.oidc_client_secret" = {
        owner = "arcane";
        group = "arcane";
        mode = "0400";
      };

      sops.templates."arcane.env" = {
        owner = "arcane";
        group = "arcane";
        mode = "0400";
        content = ''
          ENCRYPTION_KEY=${config.sops.placeholder."arcane.encryption_key"}
          JWT_SECRET=${config.sops.placeholder."arcane.jwt_secret"}
          OIDC_CLIENT_SECRET=${config.sops.placeholder."arcane.oidc_client_secret"}
        '';
      };

      home-manager.users.arcane = {
        imports = [ inputs.quadlet-nix.homeManagerModules.quadlet ];

        home.stateVersion = lib.mkDefault "25.11";

        virtualisation.quadlet.containers.arcane = {
          autoStart = true;
          containerConfig = {
            image = "ghcr.io/getarcaneapp/arcane:v2.15.1";
            publishPorts = [ "127.0.0.1:3552:3552" ];
            # Maps the container's internal user 1:1 onto the host "arcane"
            # uid/gid, so /app/data (owned by arcane:arcane above) is
            # writable without the old rootful setup's PUID/PGID dance.
            userns = "keep-id";
            # pasta runs with --no-map-gw, so 10.0.2.2 is mapped to the host loopback for auth and the socket proxy.
            networks = [ "pasta:--map-host-loopback,10.0.2.2" ];
            addHosts = [
              "auth.${domain}:10.0.2.2"
              "socket-proxy:10.0.2.2"
            ];
            volumes = [ "/srv/appdata/arcane:/app/data" ];
            environments = {
              DOCKER_HOST = "tcp://socket-proxy:2375";
              APP_URL = "https://oci.${domain}";
              LOG_LEVEL = "info";
              LOG_JSON = "false";
              OIDC_ENABLED = "true";
              OIDC_CLIENT_ID = "arcane";
              OIDC_ISSUER_URL = "https://auth.${domain}";
              OIDC_SCOPES = "openid profile email groups";
              DATABASE_URL = "file:data/arcane.db?_pragma=journal_mode(WAL)&_pragma=busy_timeout(2500)&_txlock=immediate";
            };
            environmentFiles = [ arcaneEnvPath ];
          };
        };
      };
    };
}
