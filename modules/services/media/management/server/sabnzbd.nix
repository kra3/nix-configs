{ config, lib, ... }:
{
  users.groups.media = {
    gid = 2000;
  };

  services.sabnzbd = {
    enable = true;
    configFile = "/var/lib/sabnzbd/sabnzbd.ini";
    openFirewall = true;
  };

  users.users.sabnzbd.extraGroups = [ "media" ];

  systemd.services.sabnzbd = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig.ExecStart = lib.mkForce "${lib.getBin config.services.sabnzbd.package}/bin/sabnzbd -d -f ${config.services.sabnzbd.configFile} -s 10.0.50.4:8080";
    serviceConfig.EnvironmentFile = [ "/run/secrets/media.sabnzbd.env" ];
  };
}
