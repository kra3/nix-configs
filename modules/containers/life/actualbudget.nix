{
  flake.nixosModules.containers-life-actualbudget = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.life;
    ip = config.vars.network.podmanAddresses.actualbudget;
  in
  {
    imports = [ flakeModules.nixos.services-finance-actualbudget ];

    sops.secrets."life.actualbudget.oidc_client_secret" = { };

    sops.templates."life.actualbudget.env" = {
      owner = "root";
      group = "life";
      mode = "0440";
      content = ''
        ACTUAL_OPENID_DISCOVERY_URL=https://auth.${config.vars.acme.domain}/.well-known/openid-configuration
        ACTUAL_OPENID_CLIENT_ID=actualbudget
        ACTUAL_OPENID_CLIENT_SECRET=${config.sops.placeholder."life.actualbudget.oidc_client_secret"}
        ACTUAL_OPENID_SERVER_HOSTNAME=https://actualbudget.${config.vars.acme.domain}
        ACTUAL_OPENID_AUTH_METHOD=oauth2
      '';
    };

    virtualisation.quadlet.containers.actualbudget = {
      containerConfig = {
        # Pinned to its current dynamically-assigned IP — see
        # media-mgmt/radarr.nix for why. IP centralized in vars.nix
        # (podmanAddresses.actualbudget).
        networks = [ "${network.ref}:ip=${ip}" ];
        # OIDC login calls auth.${domain} directly; route via the bridge
        # gateway since the LAN/public IP doesn't route back in from here.
        addHosts = [
          "auth.${config.vars.acme.domain}:10.3.0.1"
        ];
        volumes = [
          "/srv/appdata/life/actualbudget:/data"
        ];
        environments = {
          # Forces a restart on env content changes — see authelia.nix's
          # RESTART_TRIGGER_CONFIG_HASH for why this is needed.
          RESTART_TRIGGER_CONFIG_HASH = builtins.hashString "sha256" config.sops.templates."life.actualbudget.env".content;
        };
        environmentFiles = [ config.sops.templates."life.actualbudget.env".path ];
        # Sized from ~21h process-exporter peak + safety margin.
        memory = "256Mi";
        podmanArgs = [ "--cpus=1" ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "life-network.service" ]; };

    # No forwardAuth: authenticates natively via its own OIDC login (like Arcane).
    services.nginx.virtualHosts."actualbudget.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://${ip}:5006";
    };
  };
}
