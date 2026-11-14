{
  flake.nixosModules.services-second-brain-clipper =
    {
      config,
      lib,
      pkgs,
      inputs,
      flakeLib,
      ...
    }:
    let
      cfg = config.services.secondBrain.clipper;
      brain = config.services.secondBrain.brains.${cfg.brain} or null;
      user = "second-brain";
      stateDir = "/srv/appdata/second-brain/clipper";
      domain = config.vars.acme.domain;
      unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
      python = pkgs.python3.withPackages (ps: [ ps.faster-whisper ]);
      claude-code = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
    in
    {
      options.services.secondBrain.clipper = {
        enable = lib.mkEnableOption "the share-sheet clipper: video link to transcript to a brain's inbox note";
        brain = lib.mkOption {
          type = lib.types.str;
          default = "home";
          description = "Which services.secondBrain.brains entry receives the notes.";
        };
        hostName = lib.mkOption {
          type = lib.types.str;
          default = "clip.${domain}";
          description = "nginx vhost the iOS Shortcut posts to (LAN and Tailscale only).";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 8766;
        };
        inboxFolder = lib.mkOption {
          type = lib.types.str;
          default = "0 Inbox";
        };
        whisperModel = lib.mkOption {
          type = lib.types.str;
          default = "small";
          description = "faster-whisper model, used only when the platform has no subtitles.";
        };
        summaryModel = lib.mkOption {
          type = lib.types.str;
          default = "claude-haiku-5-5";
        };
        maxDurationMinutes = lib.mkOption {
          type = lib.types.ints.positive;
          default = 120;
        };
        instagramCookies = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Pass a Netscape cookies.txt (sops key second-brain.clipper.cookies) to yt-dlp.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = brain != null && brain.enable && brain.sync.enable;
            message = "services.secondBrain.clipper.brain = \"${cfg.brain}\" must be an enabled brain with sync on: notes reach your devices through its git sync.";
          }
        ];

        sops.secrets = {
          "second-brain.clipper.token" = { };
          "second-brain.clipper.claude_oauth_token" = { };
        }
        // lib.optionalAttrs cfg.instagramCookies {
          "second-brain.clipper.cookies" = { };
        };

        systemd.tmpfiles.rules = [ "d ${stateDir} 0700 ${user} ${user} - -" ];

        systemd.services.second-brain-clipper = {
          description = "Video link to transcript to a note in the ${cfg.brain} brain";
          wants = [ "network-online.target" ];
          after = [
            "network-online.target"
            "second-brain-${cfg.brain}-sync.service"
          ];
          wantedBy = [ "multi-user.target" ];
          path = [
            unstable.yt-dlp # extractors break often; unstable gets the fixes first
            pkgs.ffmpeg-headless
            claude-code # summaries run through the CLI on the subscription, not the metered API
          ];
          environment = {
            VAULT_DIR = if brain != null then brain.vaultDir else ""; # assertion above reports a bad brain
            INBOX_FOLDER = cfg.inboxFolder;
            STATE_DIR = stateDir;
            PORT = toString cfg.port;
            WHISPER_MODEL = cfg.whisperModel;
            SUMMARY_MODEL = cfg.summaryModel;
            MAX_DURATION_SECONDS = toString (cfg.maxDurationMinutes * 60);
            HF_HOME = "${stateDir}/models";
            HOME = stateDir;
          };
          serviceConfig =
            flakeLib.deployment-hardening.mkServiceSandbox {
              readWritePaths = [ "/srv/appdata/second-brain" ];
            }
            // {
              User = user;
              Group = user;
              UMask = "0007";
              ExecStart = "${python}/bin/python3 ${./clipper.py}";
              LoadCredential = [
                "token:${config.sops.secrets."second-brain.clipper.token".path}"
                "claude-oauth-token:${config.sops.secrets."second-brain.clipper.claude_oauth_token".path}"
              ]
              ++ lib.optional cfg.instagramCookies "cookies:${
                config.sops.secrets."second-brain.clipper.cookies".path
              }";
              Restart = "on-failure";
              RestartSec = 10;
              # Whisper on CPU must not starve Frigate or Home Assistant.
              Nice = 10;
              CPUWeight = 20;
              MemoryMax = "4G";
            };
        };

        services.nginx.virtualHosts.${cfg.hostName} = flakeLib.nginx.mkProxyVhost {
          inherit domain;
          cidrs = config.vars.network.nginxAllowCidrs;
          upstream = "http://127.0.0.1:${toString cfg.port}";
          websockets = false;
          # Bearer token in the app instead of Authelia: an iOS Shortcut can't do the login flow.
          locationExtraConfig = "client_max_body_size 64k;";
        };
      };
    };
}
