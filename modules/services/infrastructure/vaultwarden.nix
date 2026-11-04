{
  flake.nixosModules.services-infrastructure-vaultwarden =
    {
      config,
      lib,
      flakeLib,
      ...
    }:
    {
      virtualisation.quadlet.containers.vaultwarden = {
        containerConfig = {
          image = "docker.io/vaultwarden/server:1.37.5";
          # No publishPorts: see services/media/acquisition/radarr.nix — nginx
          # routes to a pinned bridge IP instead (set at the call site).
          logDriver = "journald";
          environments = {
            TZ = "UTC";
            ROCKET_PORT = "8080";
            DOMAIN = "https://vault.${config.vars.acme.domain}";
            # Accounts are created by invitation from /admin only. Without SMTP,
            # an invited address can register directly on the login page.
            SIGNUPS_ALLOWED = "false";
            INVITATIONS_ALLOWED = "true";
            SHOW_PASSWORD_HINT = "false";
            # nginx sets X-Real-IP; this is what lands in the failed-login log
            # lines that the fail2ban jail below matches.
            IP_HEADER = "X-Real-IP";
          };
        };
      };

      environment.etc."alloy/vaultwarden.alloy".text = flakeLib.observability.mkAlloyJournalSource {
        name = "vaultwarden";
        hostName = config.networking.hostName;
      };

      # LAN is in fail2ban's ignoreIP, so in practice this only bans tailnet peers.
      services.fail2ban.jails.vaultwarden = lib.mkIf config.services.fail2ban.enable {
        settings = {
          enabled = true;
          backend = "systemd";
          journalmatch = "_SYSTEMD_UNIT=vaultwarden.service";
          port = "443";
          maxretry = 5;
        };
        filter.Definition = {
          failregex = ''
            ^.*Username or password is incorrect\. Try again\. IP: <ADDR>\. Username:.*$
            ^.*Invalid admin token\. IP: <ADDR>.*$
          '';
          ignoreregex = "";
        };
      };
    };
}
