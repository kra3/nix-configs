{ config, lib, ... }:
{
  users.groups.media = {
    gid = 2000;
  };

  services.lidarr = {
    enable = true;
    openFirewall = true;
    settings = {
      server = {
        bindaddress = "10.0.50.4";
        port = 8686;
      };
    };
    environmentFiles = [ "/run/secrets/media.lidarr.env" ];
  };

  users.users.lidarr = {
    extraGroups = [ "media" ];
  };

  systemd.services.lidarr = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/lidarr/.config 0750 lidarr lidarr - -"
    "d /var/lib/lidarr/.config/Lidarr 0750 lidarr lidarr - -"
    "d /var/lib/lidarr/.config/Lidarr/logs 0750 lidarr lidarr - -"
    "f /var/lib/lidarr/.config/Lidarr/logs/lidarr.txt 0640 lidarr lidarr - -"
  ];

  services.logrotate.settings.lidarr = {
    files = [
      "/var/lib/lidarr/.config/Lidarr/logs/*.txt"
    ];
    rotate = 1;
    frequency = "hourly";
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    copytruncate = true;
    su = "lidarr lidarr";
  };

  environment.etc."alloy/lidarr.alloy".text = ''
    loki.source.file "lidarr" {
      targets = [
        {
          __path__ = "/var/lib/lidarr/.config/Lidarr/logs/lidarr.txt",
          job = "lidarr",
          host = "${config.networking.hostName}",
          role = "${if config.boot.isContainer then "container" else "host"}",
        },
      ]
      forward_to = [loki.write.default.receiver]
    }
  '';
}
