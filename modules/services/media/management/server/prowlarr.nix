{ lib, ... }:
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
}
