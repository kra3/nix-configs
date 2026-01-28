{ config, lib, ... }:
{
  users.groups.media = {
    gid = 2000;
  };

  services.prowlarr = {
    enable = true;
    openFirewall = true;
    settings = {
      server = {
        bindaddress = "10.0.50.4";
        port = 9696;
      };
    };
    environmentFiles = [ "/run/secrets/media.prowlarr.env" ];
  };

  users.users.prowlarr = {
    isSystemUser = true;
    group = "prowlarr";
    extraGroups = [ "media" ];
  };
  users.groups.prowlarr = { };

  systemd.services.prowlarr = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "prowlarr";
      Group = "prowlarr";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/prowlarr 0750 prowlarr prowlarr - -"
    "d /var/lib/prowlarr/logs 0750 prowlarr prowlarr - -"
    "f /var/lib/prowlarr/logs/prowlarr.txt 0640 prowlarr prowlarr - -"
  ];

  services.logrotate.settings.prowlarr = {
    files = [
      "/var/lib/prowlarr/logs/*.txt"
    ];
    rotate = 1;
    frequency = "hourly";
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    copytruncate = true;
    su = "prowlarr prowlarr";
  };

  environment.etc."alloy/prowlarr.alloy".text = ''
    loki.source.file "prowlarr" {
      targets = [
        {
          __path__ = "/var/lib/prowlarr/logs/prowlarr.txt",
          job = "prowlarr",
          host = "${config.networking.hostName}",
          role = "${if config.boot.isContainer then "container" else "host"}",
        },
      ]
      forward_to = [loki.write.default.receiver]
    }
  '';
}
