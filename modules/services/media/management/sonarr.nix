{ config, lib, ... }:
{
  users.groups.media = {
    gid = 2000;
  };

  services.sonarr = {
    enable = true;
    openFirewall = true;
    settings = {
      server = {
        bindaddress = "10.0.50.4";
        port = 8989;
      };
    };
    environmentFiles = [ "/run/secrets/media.sonarr.env" ];
  };

  users.users.sonarr = {
    extraGroups = [ "media" ];
  };

  systemd.services.sonarr = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/sonarr/.config 0750 sonarr sonarr - -"
    "d /var/lib/sonarr/.config/NzbDrone 0750 sonarr sonarr - -"
    "d /var/lib/sonarr/.config/NzbDrone/logs 0750 sonarr sonarr - -"
    "f /var/lib/sonarr/.config/NzbDrone/logs/sonarr.txt 0640 sonarr sonarr - -"
  ];

  services.logrotate.settings.sonarr = {
    files = [
      "/var/lib/sonarr/.config/NzbDrone/logs/*.txt"
    ];
    rotate = 1;
    frequency = "hourly";
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    copytruncate = true;
    su = "sonarr sonarr";
  };

  environment.etc."alloy/sonarr.alloy".text = ''
    loki.source.file "sonarr" {
      targets = [
        {
          __path__ = "/var/lib/sonarr/.config/NzbDrone/logs/sonarr.txt",
          job = "sonarr",
          host = "${config.networking.hostName}",
          role = "${if config.boot.isContainer then "container" else "host"}",
        },
      ]
      forward_to = [loki.write.default.receiver]
    }
  '';
}
