{ config, lib, pkgs, ... }:
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
      PermissionsStartOnly = true;
      UMask = lib.mkForce "0027";
    };
    preStart = lib.mkAfter ''
      ${pkgs.coreutils}/bin/install -m 0640 -o music-assistant -g music-assistant /dev/null \
        /var/lib/music-assistant/musicassistant.log
    '';
    postStart = lib.mkAfter ''
      ${pkgs.coreutils}/bin/chmod 0640 /var/lib/music-assistant/musicassistant.log || true
    '';
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/music-assistant 0750 music-assistant music-assistant - -"
    "Z /var/lib/music-assistant/musicassistant.log 0640 music-assistant music-assistant - -"
  ];

  environment.systemPackages = [
    pkgs.snapcast
  ];

  services.logrotate.settings.music-assistant = {
    files = [
      "/var/lib/music-assistant/*.log"
    ];
    rotate = 1;
    frequency = "hourly";
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    copytruncate = true;
    su = "music-assistant music-assistant";
  };

  environment.etc."alloy/music-assistant.alloy".text = ''
    loki.source.file "music_assistant" {
      targets = [
        {
          __path__ = "/var/lib/music-assistant/musicassistant.log",
          job = "music-assistant",
          host = "${config.networking.hostName}",
          role = "${if config.boot.isContainer then "container" else "host"}",
        },
      ]
      forward_to = [loki.write.default.receiver]
    }
  '';
}
