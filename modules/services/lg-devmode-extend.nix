{
  flake.nixosModules.services-lg-devmode-extend =
    { config, pkgs, ... }:
    let
      extend = pkgs.writeShellApplication {
        name = "lg-devmode-extend";
        runtimeInputs = [
          pkgs.curl
          pkgs.jq
        ];
        text = ''
          token=$(<"$CREDENTIALS_DIRECTORY/token")
          resp=$(curl -fsS "https://developer.lge.com/secure/ResetDevModeSession.dev?sessionToken=$token")
          echo "$resp"
          jq -e '.result == "success"' <<<"$resp" >/dev/null
        '';
      };
    in
    {
      sops.secrets."lg_tv.devmode_token" = { };

      systemd.services.lg-devmode-extend = {
        description = "Extend LG TV webOS Developer Mode session";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          LoadCredential = [ "token:${config.sops.secrets."lg_tv.devmode_token".path}" ];
          ExecStart = "${extend}/bin/lg-devmode-extend";
        };
      };

      systemd.timers.lg-devmode-extend = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "weekly";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
      };
    };
}
