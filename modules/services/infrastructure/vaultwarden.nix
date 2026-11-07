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
            # Accounts are created by invitation from /admin only; the invite
            # arrives by email (SMTP below) with a sign-up link.
            SIGNUPS_ALLOWED = "false";
            INVITATIONS_ALLOWED = "true";
            SHOW_PASSWORD_HINT = "false";
            # No hints at all: a hint is stored server-side in plaintext and
            # only ever weakens the master password.
            PASSWORD_HINTS_ALLOWED = "false";
            # Only the admin can create organizations (used for sharing).
            ORG_CREATION_USERS = "kra3@${config.vars.acme.domain}";
            # nginx sets X-Real-IP; this is what lands in the failed-login log
            # lines that the fail2ban jail below matches.
            IP_HEADER = "X-Real-IP";
            # Mobile push via Bitwarden's relay. The installation ID/key come
            # from the env file (container module); the relay URIs must match
            # the region the installation was registered in (EU).
            PUSH_ENABLED = "true";
            PUSH_RELAY_URI = "https://api.bitwarden.eu";
            PUSH_IDENTITY_URI = "https://identity.bitwarden.eu";
            # "Log in with SSO" via Authelia, alongside email+password (not SSO-only).
            # Existing accounts link by matching email; the client secret comes
            # from the env file (container module).
            SSO_ENABLED = "true";
            SSO_ONLY = "false";
            SSO_AUTHORITY = "https://auth.${config.vars.acme.domain}";
            SSO_CLIENT_ID = "vaultwarden";
            SSO_SCOPES = "email profile";
            SSO_PKCE = "true";
            SSO_AUTH_ONLY_NOT_SESSION = "true";
            SSO_SIGNUPS_MATCH_EMAIL = "true";
            # Invites, new-device alerts, email 2FA and emergency access. Same
            # Gmail account + app password as alarm-person-photos (home-auto.nix);
            # SMTP_PASSWORD comes from the env file (container module).
            SMTP_HOST = "smtp.gmail.com";
            SMTP_PORT = "587";
            SMTP_SECURITY = "starttls";
            SMTP_FROM = config.vars.acme.email;
            SMTP_FROM_NAME = "Vaultwarden";
            SMTP_USERNAME = config.vars.acme.email;
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
