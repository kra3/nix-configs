{
  # Independent "is sutala reachable at all" watchdog, deliberately outside
  # sutala's own Grafana/Prometheus/Alertmanager pipeline -- that pipeline
  # runs ON sutala, so it can't alert on sutala itself being down. This
  # checks from surasa instead and pushes straight to the same Telegram bot
  # sutala's monitoring stack uses (modules/containers/monitoring.nix), so no
  # new bot/secret is needed -- just this host also being a sops recipient.
  #
  # Deliberately a plain script+timer, not a second blackbox_exporter +
  # Prometheus: this is a 1GB RPi already running DNS + PipeWire/Bluetooth,
  # and a coarse reachability check doesn't need a metrics pipeline.
  flake.nixosModules.services-monitoring-sutala-watchdog =
  { config, pkgs, ... }:
  let
    sutalaIp = "192.168.1.10";
    stateFile = "/var/lib/sutala-watchdog/down";

    # Token/chat-id are read into a curl -K config from stdin (heredoc),
    # never as a curl argv element, so neither shows up in `ps` -- same
    # care as adguard.nix's preStart credential handling.
    checkScript = pkgs.writeShellScript "sutala-watchdog-run" ''
      set -euo pipefail
      mkdir -p "$(dirname ${stateFile})"

      send() {
        local token chatid
        token=$(cat "$CREDENTIALS_DIRECTORY/bottoken")
        chatid=$(cat "$CREDENTIALS_DIRECTORY/chatid")
        curl -sS --max-time 10 -K - <<CURLCFG
      url = "https://api.telegram.org/bot$token/sendMessage"
      data = "chat_id=$chatid"
      data-urlencode = "text=$1"
      CURLCFG
      }

      if ping -c 3 -W 2 ${sutalaIp} >/dev/null 2>&1; then
        if [ -f ${stateFile} ]; then
          rm -f ${stateFile}
          send "sutala is back up (reachable again from surasa)."
        fi
        exit 0
      fi

      if [ -f ${stateFile} ]; then
        # Already alerted for this outage -- don't spam.
        exit 0
      fi
      touch ${stateFile}
      send "sutala is unreachable from surasa (3 pings to ${sutalaIp} failed)."
    '';
  in
  {
    systemd.services.sutala-watchdog = {
      description = "Check sutala reachability, alert via Telegram on change";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [
        pkgs.iputils
        pkgs.curl
      ];
      serviceConfig = {
        Type = "oneshot";
        LoadCredential = [
          "bottoken:${config.sops.secrets."monitoring.grafana.telegram_bot_token".path}"
          "chatid:${config.sops.secrets."monitoring.grafana.telegram_chat_id".path}"
        ];
        ExecStart = checkScript;
      };
    };

    systemd.timers.sutala-watchdog = {
      description = "Periodic sutala reachability check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitActiveSec = "2m";
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/sutala-watchdog 0750 root root - -"
    ];

    sops.secrets."monitoring.grafana.telegram_bot_token" = { };
    sops.secrets."monitoring.grafana.telegram_chat_id" = { };
  };
}
