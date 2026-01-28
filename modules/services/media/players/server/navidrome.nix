{ ... }:
{
  users.groups.media = {
    gid = 2000;
  };

  services.navidrome = {
    enable = true;
    openFirewall = false;
    settings = {
      Address = "0.0.0.0";
      Port = 4533;
      MusicFolder = "/data/library/music";
      DataFolder = "/var/lib/navidrome/data";
    };
  };

  users.users.navidrome = {
    extraGroups = [ "media" ];
  };

  systemd.services.navidrome = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

}
