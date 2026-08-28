{
  flake.nixosModules.services-virtualisation-arcane =
  { config, lib, flakeLib, ... }:
  {
    virtualisation.oci-containers.containers.arcane = {
      image = "ghcr.io/getarcaneapp/arcane:v2.4.0";
      autoStart = true;
      ports = [ "127.0.0.1:3552:3552" ];
      volumes = [
        "/run/podman/podman.sock:/var/run/docker.sock"
        "/srv/appdata/arcane:/app/data"
        "/sys/fs/cgroup:/sys/fs/cgroup:ro"
      ];
      environment = {
        APP_URL = "https://oci.${config.vars.acme.domain}";
        PUID = "1000";
        PGID = "981";
        LOG_LEVEL = "info";
        LOG_JSON = "false";
        OIDC_ENABLED = "false";
        DATABASE_URL = "file:data/arcane.db?_pragma=journal_mode(WAL)&_pragma=busy_timeout(2500)&_txlock=immediate";
      };
      environmentFiles = [
        config.sops.templates."arcane.env".path
      ];
    };

    services.nginx.virtualHosts."oci.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:3552";
      vhostExtraConfig = ''
        add_header X-Frame-Options "*";
        add_header X-Robots-Tag "noindex, nofollow";
      '';
    };

    systemd.tmpfiles.rules = [
      "d /srv/appdata/arcane 0755 root root - -"
      "d /srv/appdata/arcane/projects 0755 root root - -"
    ];

    sops.secrets."arcane.encryption_key" = { };
    sops.secrets."arcane.jwt_secret" = { };

    sops.templates."arcane.env" = {
      content = ''
        ENCRYPTION_KEY=${config.sops.placeholder."arcane.encryption_key"}
        JWT_SECRET=${config.sops.placeholder."arcane.jwt_secret"}
      '';
    };
  };
}
