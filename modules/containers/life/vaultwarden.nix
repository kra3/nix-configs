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
        '';
      };

      virtualisation.quadlet.containers.vaultwarden = {
        containerConfig = {
          # Pinned IP centralized in vars.nix (podmanAddresses.vaultwarden) —
          # see media-mgmt/radarr.nix for why.
          networks = [ "${network.ref}:ip=${ip}" ];
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
      services.nginx.virtualHosts."vault.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://${ip}:8080";
        # Attachments / Sends.
        vhostExtraConfig = "client_max_body_size 128m;";
      };
    };
}
