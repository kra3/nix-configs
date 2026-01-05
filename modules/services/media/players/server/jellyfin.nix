{
  users.groups.media = {
    gid = 2000;
  };

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  users.users.jellyfin = {
    extraGroups = [
      "media"
      "render"
      "video"
    ];
  };

  systemd.services.jellyfin = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}
