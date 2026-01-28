{ config, lib, ... }:
{
  users.groups.media = {
    gid = 2000;
  };

  services.radarr = {
    enable = true;
    openFirewall = true;
    settings = {
      server = {
        bindaddress = "10.0.50.4";
        port = 7878;
      };
    };
    environmentFiles = [ "/run/secrets/media.radarr.env" ];
  };

  users.users.radarr = {
    extraGroups = [ "media" ];
  };

  systemd.services.radarr = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/radarr/.config 0750 radarr radarr - -"
    "d /var/lib/radarr/.config/Radarr 0750 radarr radarr - -"
    "d /var/lib/radarr/.config/Radarr/logs 0750 radarr radarr - -"
    "f /var/lib/radarr/.config/Radarr/logs/radarr.txt 0640 radarr radarr - -"
  ];

  services.logrotate.settings.radarr = {
    files = [
      "/var/lib/radarr/.config/Radarr/logs/*.txt"
    ];
    rotate = 1;
    frequency = "hourly";
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    copytruncate = true;
    su = "radarr radarr";
  };

  environment.etc."alloy/radarr.alloy".text = ''
    loki.source.file "radarr" {
      targets = [
        {
          __path__ = "/var/lib/radarr/.config/Radarr/logs/radarr.txt",
          job = "radarr",
          host = "${config.networking.hostName}",
          role = "${if config.boot.isContainer then "container" else "host"}",
        },
      ]
      forward_to = [loki.write.default.receiver]
    }
  '';
}
