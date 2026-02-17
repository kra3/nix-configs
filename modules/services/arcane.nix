{ config, lib, ... }:
let
  allowBlock = ''
    ${lib.concatStringsSep "\n" (map (cidr: "allow ${cidr};") config.vars.network.nginxAllowCidrs)}
    deny all;
  '';
  isArcaneMedia = config.vars.media.backend == "arcane";
in
{
  virtualisation.oci-containers = {
    backend = "docker";
    containers.arcane = {
      image = "ghcr.io/getarcaneapp/arcane:latest";
      autoStart = true;
      ports = [ "3552:3552" ];
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock"
        "/srv/appdata/arcane:/app/data"
        "/sys/fs/cgroup:/sys/fs/cgroup:ro"
      ];
      environment = {
        APP_URL = "https://oci.karunagath.in";
        PUID = "1000";
        PGID = "1000";
        LOG_LEVEL = "info";
        LOG_JSON = "false";
        OIDC_ENABLED = "false";
        DATABASE_URL = "file:data/arcane.db?_pragma=journal_mode(WAL)&_pragma=busy_timeout(2500)&_txlock=immediate";
      };
      environmentFiles = [
        config.sops.templates."arcane.env".path
      ];
    };
  };

  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  services.nginx.virtualHosts."oci.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = ''
      ${allowBlock}
      add_header X-Frame-Options "*";
      add_header X-Robots-Tag "noindex, nofollow";
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:3552";
      proxyWebsockets = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/appdata/arcane 0755 root root - -"
    "d /srv/appdata/arcane/projects 0755 root root - -"
  ] ++ lib.optionals isArcaneMedia [
    "d /srv/appdata/arcane/projects/media-mgmt 0755 root root - -"
  ];

  environment.etc."arcane/stacks/media-mgmt/compose.yaml" = lib.mkIf isArcaneMedia {
    source = ../../stacks/media-mgmt/compose.yaml;
  };

  sops.secrets."arcane.encryption_key" = {};
  sops.secrets."arcane.jwt_secret" = {};

  # Media stack secrets (when using arcane backend)
  sops.secrets."media.radarr.api_key" = lib.mkIf isArcaneMedia {};
  sops.secrets."media.sonarr.api_key" = lib.mkIf isArcaneMedia {};
  sops.secrets."media.lidarr.api_key" = lib.mkIf isArcaneMedia {};
  sops.secrets."media.prowlarr.api_key" = lib.mkIf isArcaneMedia {};
  sops.secrets."media.bazarr.api_key" = lib.mkIf isArcaneMedia {};
  sops.secrets."media.sabnzbd.api_key" = lib.mkIf isArcaneMedia {};
  sops.secrets."media.sabnzbd.nzb_key" = lib.mkIf isArcaneMedia {};
  sops.secrets."media.jellyseerr.api_key" = lib.mkIf isArcaneMedia {};

  sops.templates."arcane.env" = {
    content = ''
      ENCRYPTION_KEY=${config.sops.placeholder."arcane.encryption_key"}
      JWT_SECRET=${config.sops.placeholder."arcane.jwt_secret"}
    '';
  };

  sops.templates."arcane.stack.media-mgmt.env" = lib.mkIf isArcaneMedia {
    # Rendered to /run/secrets/rendered/arcane.stack.media-mgmt.env
    # Copied to project dir by systemd service below
    mode = "0644";
    content = ''
      RADARR__API_KEY=${config.sops.placeholder."media.radarr.api_key"}
      SONARR__API_KEY=${config.sops.placeholder."media.sonarr.api_key"}
      LIDARR__API_KEY=${config.sops.placeholder."media.lidarr.api_key"}
      PROWLARR__API_KEY=${config.sops.placeholder."media.prowlarr.api_key"}
      BAZARR__API_KEY=${config.sops.placeholder."media.bazarr.api_key"}
      SABNZBD__API_KEY=${config.sops.placeholder."media.sabnzbd.api_key"}
      SABNZBD__NZB_KEY=${config.sops.placeholder."media.sabnzbd.nzb_key"}
      JELLYSEERR__API_KEY=${config.sops.placeholder."media.jellyseerr.api_key"}
      RECYCLARR__RADARR__API_KEY=${config.sops.placeholder."media.radarr.api_key"}
      RECYCLARR__SONARR__API_KEY=${config.sops.placeholder."media.sonarr.api_key"}
    '';
  };

  # Copy compose.yaml and .env to arcane project directory (symlinks don't work with Arcane)
  systemd.services.arcane-media-mgmt-setup = lib.mkIf isArcaneMedia {
    description = "Setup Arcane media-mgmt project files";
    wantedBy = [ "multi-user.target" ];
    after = [ "sops-nix.service" ];
    restartIfChanged = true;
    restartTriggers = [
      config.environment.etc."arcane/stacks/media-mgmt/compose.yaml".source
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /srv/appdata/arcane/projects/media-mgmt
      cp -f /etc/arcane/stacks/media-mgmt/compose.yaml /srv/appdata/arcane/projects/media-mgmt/compose.yaml
      cp -f /run/secrets/rendered/arcane.stack.media-mgmt.env /srv/appdata/arcane/projects/media-mgmt/.env
      chmod 644 /srv/appdata/arcane/projects/media-mgmt/compose.yaml
      chmod 644 /srv/appdata/arcane/projects/media-mgmt/.env
    '';
  };
}
