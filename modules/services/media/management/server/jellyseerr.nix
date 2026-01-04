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
}
