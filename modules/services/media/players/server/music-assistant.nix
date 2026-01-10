{ lib, pkgs, ... }:
{
  users.groups.media = {
    gid = 2000;
  };
  users.groups.music-assistant = { };

  services.music-assistant = {
    enable = true;
    providers = [
      # "apple_music"
      "builtin"
      "builtin_player"
      "chromecast"
      "dlna"
      "filesystem_local"
      "hass"
      "hass_players"
      "lastfm_scrobble"
      "opensubsonic"
      "player_group"
      "radiobrowser"
      "snapcast"
      "spotify"
      "spotify_connect"
    ];
    extraOptions = [
      "--config"
      "/var/lib/music-assistant"
    ];
  };

  users.users.music-assistant = {
    isSystemUser = true;
    group = "music-assistant";
    extraGroups = [ "media" ];
  };

  systemd.services.music-assistant = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "music-assistant";
      Group = "music-assistant";
    };
  };

  environment.systemPackages = [
    pkgs.snapcast
  ];
}
