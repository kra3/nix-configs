{
  flake.nixosModules.containers-life-vaultwarden =
    {
      config,
      flakeLib,
      flakeModules,
      ...
    }:
    let
      network = config.virtualisation.quadlet.networks.life;
      ip = config.vars.network.podmanAddresses.vaultwarden;
    in
    {
      imports = [ flakeModules.nixos.services-infrastructure-vaultwarden ];

      # Argon2id PHC string, not the raw token — generate with
      # `podman run --rm -it docker.io/vaultwarden/server:<tag> /vaultwarden hash`.
      sops.secrets."life.vaultwarden.admin_token_hash" = { };
      # From bitwarden.com/host (EU region). Lets iOS/iPadOS get instant sync
      # via Bitwarden's push relay -> APNs; the relay only sees device push
      # tokens and "sync now" signals, never vault data.
      sops.secrets."life.vaultwarden.push_installation_id" = { };
      sops.secrets."life.vaultwarden.push_installation_key" = { };
      # Plaintext half of authelia.oidc_clients.vaultwarden.client_secret_hash.
      sops.secrets."life.vaultwarden.sso_client_secret" = { };
      # Gmail app password, shared with alarm-person-photos (home-auto.nix).
      sops.secrets."alarm.smtp_password" = { };

      sops.templates."life.vaultwarden.env" = {
        owner = "root";
        group = "life";
        mode = "0440";
        # The RESTART_TRIGGER hash below only sees placeholders, so a rotated
        # secret value (e.g. a new admin token) needs this to take effect.
        restartUnits = [ "vaultwarden.service" ];
        content = ''
          ADMIN_TOKEN=${config.sops.placeholder."life.vaultwarden.admin_token_hash"}
          PUSH_INSTALLATION_ID=${config.sops.placeholder."life.vaultwarden.push_installation_id"}
          PUSH_INSTALLATION_KEY=${config.sops.placeholder."life.vaultwarden.push_installation_key"}
          SSO_CLIENT_SECRET=${config.sops.placeholder."life.vaultwarden.sso_client_secret"}
          SMTP_PASSWORD=${config.sops.placeholder."alarm.smtp_password"}
        '';
      };

      virtualisation.quadlet.containers.vaultwarden = {
        containerConfig = {
          # Pinned IP centralized in vars.nix (podmanAddresses.vaultwarden) —
          # see media-mgmt/radarr.nix for why.
          networks = [ "${network.ref}:ip=${ip}" ];
          # SSO discovery/token calls hit auth.${domain}; route via the bridge
          # gateway since the LAN/public IP doesn't route back in from here
          # (same as actualbudget.nix).
          addHosts = [
            "auth.${config.vars.acme.domain}:10.3.0.1"
          ];
          # SQLite DB, attachments, RSA keys. Lives under rpool/appdata, so it's
          # covered by sanoid's hourly snapshots + the USB replica (backup-usb.nix).
          volumes = [
            "/srv/appdata/life/vaultwarden:/data"
          ];
          environments = {
            # Forces a restart on env content changes — see authelia.nix's
            # RESTART_TRIGGER_CONFIG_HASH for why this is needed.
            RESTART_TRIGGER_CONFIG_HASH =
              builtins.hashString "sha256"
                config.sops.templates."life.vaultwarden.env".content;
          };
          environmentFiles = [ config.sops.templates."life.vaultwarden.env".path ];
          memory = "256m";
          podmanArgs = [ "--cpus=1" ];
        };
      }
      // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "life-network.service" ]; };

      # No forwardAuth: Bitwarden clients talk to the API directly and can't do
      # an Authelia redirect. The master password (+ per-user 2FA) is the auth;
      # nginx still restricts to LAN + tailnet via nginxAllowCidrs.
      #
      # /admin is the exception: it's browser-only, so it additionally sits behind
      # Authelia forward-auth (admin group, see authelia.nix access_control) on top
      # of ADMIN_TOKEN. Built with forwardAuth = true, then "/" swapped back to a
      # plain proxy and the forward-authed location moved to "/admin".
      services.nginx.virtualHosts."vault.${config.vars.acme.domain}" =
        let
          vhost = flakeLib.nginx.mkProxyVhost {
            domain = config.vars.acme.domain;
            cidrs = config.vars.network.nginxAllowCidrs;
            upstream = "http://${ip}:8080";
            forwardAuth = true;
            # Attachments / Sends.
            vhostExtraConfig = "client_max_body_size 128m;";
          };
        in
        vhost
        // {
          locations = vhost.locations // {
            "/" = {
              proxyPass = "http://${ip}:8080";
              proxyWebsockets = true;
            };
            "/admin" = vhost.locations."/";
          };
        };
    };
}
