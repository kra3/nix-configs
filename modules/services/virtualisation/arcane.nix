{
  flake.nixosModules.services-virtualisation-arcane =
  { config, lib, inputs, flakeLib, ... }:
  let
    domain = config.vars.acme.domain;
    arcaneEnvPath = config.sops.templates."arcane.env".path;
  in
  {
    # Runs under the dedicated "arcane" user's own rootless podman instance
    # (modules/users/arcane.nix), not the system's rootful one — a compromise
    # of this container reaches only its own unprivileged podman, not host
    # root. Isolated by construction from the app fleet's rootful quadlet
    # networks/storage; it can't see or manage sonarr/radarr/etc, which is
    # fine since deployment is handled by nix, not by Arcane.
    services.nginx.virtualHosts."oci.${domain}" = flakeLib.nginx.mkProxyVhost {
      domain = domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:3552";
      vhostExtraConfig = ''
        add_header X-Frame-Options "*";
        add_header X-Robots-Tag "noindex, nofollow";
      '';
    };

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

    sops.templates."arcane.env" = {
      owner = "arcane";
      group = "arcane";
      mode = "0400";
      content = ''
        ENCRYPTION_KEY=${config.sops.placeholder."arcane.encryption_key"}
        JWT_SECRET=${config.sops.placeholder."arcane.jwt_secret"}
      '';
    };

    home-manager.users.arcane =
      { pkgs, ... }:
      {
        imports = [ inputs.quadlet-nix.homeManagerModules.quadlet ];

        home.stateVersion = lib.mkDefault "25.11";

        # Rootless podman's API socket (ships in the podman package as
        # share/systemd/user/podman.{socket,service}) isn't enabled by
        # default the way quadlet-nix's own generated container units are —
        # Arcane needs it explicitly to talk to "its" podman at all.
        systemd.user.sockets.podman = {
          Unit.Description = "Podman API Socket";
          Socket = {
            ListenStream = "%t/podman/podman.sock";
            SocketMode = "0660";
          };
          Install.WantedBy = [ "sockets.target" ];
        };
        systemd.user.services.podman = {
          Unit = {
            Description = "Podman API Service";
            Requires = [ "podman.socket" ];
            After = [ "podman.socket" ];
          };
          Service = {
            Delegate = "true";
            Type = "exec";
            KillMode = "process";
            ExecStart = "${pkgs.podman}/bin/podman system service";
          };
        };

        virtualisation.quadlet.containers.arcane = {
          autoStart = true;
          containerConfig = {
            image = "ghcr.io/getarcaneapp/arcane:v2.4.0";
            publishPorts = [ "127.0.0.1:3552:3552" ];
            # Maps the container's internal user 1:1 onto the host "arcane"
            # uid/gid, so /app/data (owned by arcane:arcane above) is
            # writable without the old rootful setup's PUID/PGID dance.
            userns = "keep-id";
            volumes = [
              "%t/podman/podman.sock:/var/run/docker.sock"
              "/srv/appdata/arcane:/app/data"
            ];
            environments = {
              APP_URL = "https://oci.${domain}";
              LOG_LEVEL = "info";
              LOG_JSON = "false";
              OIDC_ENABLED = "false";
              DATABASE_URL = "file:data/arcane.db?_pragma=journal_mode(WAL)&_pragma=busy_timeout(2500)&_txlock=immediate";
            };
            environmentFiles = [ arcaneEnvPath ];
          };
        };
      };
  };
}
