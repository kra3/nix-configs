{ config, lib, ... }:
{
  users.groups.media = {
    gid = 2000;
  };

  services.jellyseerr = {
    enable = true;
    openFirewall = true;
    port = 5055;
    configDir = "/var/lib/jellyseerr/config";
  };

  users.users.jellyseerr = {
    isSystemUser = true;
    group = "jellyseerr";
    extraGroups = [ "media" ];
  };
  users.groups.jellyseerr = { };

  systemd.services.jellyseerr = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "jellyseerr";
      Group = "jellyseerr";
      EnvironmentFile = [ "/run/secrets/media.jellyseerr.env" ];
    };
    environment = {
      PORT = "5055";
      CONFIG_DIRECTORY = config.services.jellyseerr.configDir;
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/jellyseerr 0750 jellyseerr jellyseerr - -"
    "d /var/lib/jellyseerr/config 0750 jellyseerr jellyseerr - -"
    "d /var/lib/jellyseerr/config/logs 0750 jellyseerr jellyseerr - -"
    "f /var/lib/jellyseerr/config/logs/jellyseerr.log 0640 jellyseerr jellyseerr - -"
  ];

  services.logrotate.settings.jellyseerr = {
    files = [
      "/var/lib/jellyseerr/config/logs/*.log"
    ];
    rotate = 1;
    frequency = "hourly";
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    copytruncate = true;
    su = "jellyseerr jellyseerr";
  };

  environment.etc."alloy/jellyseerr.alloy".text = ''
    loki.source.file "jellyseerr" {
      targets = [
        {
          __path__ = "/var/lib/jellyseerr/config/logs/jellyseerr.log",
          job = "jellyseerr",
          host = "${config.networking.hostName}",
          role = "${if config.boot.isContainer then "container" else "host"}",
        },
      ]
      forward_to = [loki.write.default.receiver]
    }
  '';
}
