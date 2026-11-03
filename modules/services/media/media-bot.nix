{
  perSystem =
    { pkgs, ... }:
    {
      checks.media-bot-tests =
        pkgs.runCommand "media-bot-tests" { nativeBuildInputs = [ pkgs.python3 ]; }
          ''
            python3 ${./media-bot-test.py} ${./media-bot.py}
            touch $out
          '';
    };

  flake.nixosModules.services-media-media-bot =
    {
      config,
      lib,
      pkgs,
      flakeLib,
      ...
    }:
    let
      dryRun = false;
      addr = config.vars.network.podmanAddresses;
      secrets = config.sops.secrets;
      python = pkgs.python3.withPackages (
        p:
        [ p.python-telegram-bot ]
        ++ (p.python-telegram-bot.optional-dependencies.job-queue or [ p.apscheduler ])
      );
      args = [
        "--radarr"
        "http://${addr.radarr}:7878"
        "--sonarr"
        "http://${addr.sonarr}:8989"
        "--seerr"
        "http://${addr.seerr}:5055"
        "--maintainerr"
        "http://${addr.maintainerr}:6246"
        "--media-root"
        "/srv/media"
      ]
      ++ lib.optionals (config.time.timeZone != null) [
        "--tz"
        config.time.timeZone
      ]
      ++ lib.optional dryRun "--dry-run";
    in
    lib.mkIf config.vars.localMedia.enable {
      sops.secrets = {
        "media.bot.telegram_bot_token" = { };
        "media.bot.telegram_group_chat_id" = { };
        "media.bot.telegram_admin_user_id" = { };
        "media.radarr.api_key" = { };
        "media.sonarr.api_key" = { };
        "media.seerr.api_key" = { };
      };

      systemd.services.media-bot = {
        description = "Telegram bot for media search, requests, keep and reaper digest";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        startLimitIntervalSec = 600;
        startLimitBurst = 10;
        serviceConfig = flakeLib.deployment-hardening.mkServiceSandbox { } // {
          DynamicUser = true;
          LoadCredential = [
            "telegram-token:${secrets."media.bot.telegram_bot_token".path}"
            "group-chat-id:${secrets."media.bot.telegram_group_chat_id".path}"
            "admin-user-id:${secrets."media.bot.telegram_admin_user_id".path}"
            "radarr-key:${secrets."media.radarr.api_key".path}"
            "sonarr-key:${secrets."media.sonarr.api_key".path}"
            "seerr-key:${secrets."media.seerr.api_key".path}"
          ];
          ExecStart = "${python}/bin/python3 ${./media-bot.py} ${lib.escapeShellArgs args}";
          Restart = "on-failure";
          RestartSec = "30s";
        };
      };
    };
}
