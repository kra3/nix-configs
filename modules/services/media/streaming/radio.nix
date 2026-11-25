{
  flake.nixosModules.services-media-streaming-radio =
    { config, pkgs, ... }:
    let
      net = config.vars.network.containers.mediaPlay;
    in
    {
      sops.secrets."navidrome.radio_sync_password" = { };
      sops.secrets."music-assistant.sync_token" = { };

      systemd.services.radio-sync = {
        description = "Mirror ranjithkb.com's AIR Malayalam stations into Navidrome and Music Assistant";
        after = [
          "network-online.target"
          "container@media-play.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.python3}/bin/python3 ${./radio/sync.py} --navidrome http://${net.localAddress}:4533 --ma http://127.0.0.1:8095";
          LoadCredential = [
            "navidrome:${config.sops.secrets."navidrome.radio_sync_password".path}"
            "ma:${config.sops.secrets."music-assistant.sync_token".path}"
          ];
          DynamicUser = true;
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          Restart = "on-failure";
          RestartSec = "10min";
          TimeoutStartSec = "5min";
          MemoryMax = "128M";
        };
      };

      systemd.timers.radio-sync = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "10min";
          OnUnitActiveSec = "24h";
          RandomizedDelaySec = "30min";
        };
      };
    };
}
