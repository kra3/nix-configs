{ config, lib, ... }:
{
  users.groups.media = {
    gid = 2000;
  };

  services.bazarr = {
    enable = true;
    openFirewall = true;
    listenPort = 6767;
  };

  users.users.bazarr = {
    extraGroups = [ "media" ];
  };

  systemd.services.bazarr = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig.EnvironmentFile = [ "/run/secrets/media.bazarr.env" ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/bazarr 0750 bazarr bazarr - -"
    "d /var/lib/bazarr/log 0750 bazarr bazarr - -"
    "f /var/lib/bazarr/log/bazarr.log 0640 bazarr bazarr - -"
  ];

  services.logrotate.settings.bazarr = {
    files = [
      "/var/lib/bazarr/log/*.log"
    ];
    rotate = 1;
    frequency = "hourly";
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    copytruncate = true;
    su = "bazarr bazarr";
  };

  environment.etc."alloy/bazarr.alloy".text = ''
    loki.source.file "bazarr" {
      targets = [
        {
          __path__ = "/var/lib/bazarr/log/bazarr.log",
          job = "bazarr",
          host = "${config.networking.hostName}",
          role = "${if config.boot.isContainer then "container" else "host"}",
        },
      ]
      forward_to = [loki.write.default.receiver]
    }
  '';
}
