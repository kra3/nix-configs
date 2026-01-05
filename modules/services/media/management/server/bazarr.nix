{ pkgs, ... }:
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
}
