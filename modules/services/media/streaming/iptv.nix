{
  flake.nixosModules.services-media-streaming-iptv =
    {
      config,
      inputs,
      pkgs,
      ...
    }:
    let
      stateDir = "/var/lib/iptv";
      bind = config.vars.network.containers.mediaPlay.hostAddress;
      port = 8099;
      python = "${pkgs.python3}/bin/python3";
      channels = ./iptv/channels.tsv;
      ytDlp = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.yt-dlp;
      sandbox = {
        User = "iptv";
        Group = "iptv";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    in
    {
      users.users.iptv = {
        isSystemUser = true;
        group = "iptv";
      };
      users.groups.iptv = { };

      systemd.services.iptv-yt-resolver = {
        description = "Redirect iptv YouTube entries to a fresh live manifest";
        wantedBy = [ "multi-user.target" ];
        after = [
          "container@media-play.service"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        path = [ ytDlp ];
        environment.XDG_CACHE_HOME = "/var/cache/iptv";
        serviceConfig = sandbox // {
          ExecStart = "${python} ${./iptv/yt_resolver.py} --bind ${bind} --port ${toString port} --allow ${channels} --m3u ${stateDir}/news.m3u";
          CacheDirectory = "iptv";
          Restart = "on-failure";
          RestartSec = 10;
          MemoryMax = "256M";
        };
      };

      systemd.services.iptv-prune = {
        description = "Build the curated live-news M3U from iptv-org";
        after = [
          "network-online.target"
          "iptv-yt-resolver.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = sandbox // {
          Type = "oneshot";
          ExecStart = "${python} ${./iptv/prune_iptv.py} --allow ${channels} --out ${stateDir}/news.m3u --state ${stateDir}/state.json --yt-base http://${bind}:${toString port}";
          StateDirectory = "iptv";
          StateDirectoryMode = "0755";
          TimeoutStartSec = "10min";
          MemoryMax = "256M";
        };
      };

      systemd.timers.iptv-prune = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "6h";
          RandomizedDelaySec = "5min";
        };
      };

      networking.firewall.interfaces.ve-media-play.allowedTCPPorts = [ port ];
    };
}
