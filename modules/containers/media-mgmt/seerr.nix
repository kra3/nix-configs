{
  flake.nixosModules.containers-media-mgmt-seerr =
    {
      config,
      flakeLib,
      flakeModules,
      ...
    }:
    let
      network = config.virtualisation.quadlet.networks.media-mgmt;
      ip = config.vars.network.podmanAddresses.seerr;
    in
    {
      imports = [ flakeModules.nixos.services-media-acquisition-seerr ];

      sops.secrets."media.seerr.api_key" = { };

      sops.templates."media.seerr.env" = {
        owner = "root";
        group = "media";
        mode = "0440";
        content = "SEERR__API_KEY=${config.sops.placeholder."media.seerr.api_key"}";
      };

      virtualisation.quadlet.containers.seerr = {
        containerConfig = {
          # Pinned to its current dynamically-assigned IP — see
          # media-mgmt/radarr.nix for why. IP centralized in vars.nix
          # (podmanAddresses.seerr).
          networks = [ "${network.ref}:ip=${ip}" ];
          volumes = [
            "/srv/appdata/media-mgmt/seerr:/app/config"
          ];
          # Sized from ~21h process-exporter peak + safety margin.
          memory = "640m";
          podmanArgs = [ "--cpus=1" ];
        };
      }
      // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

      # forwardAuth stays on: this fork (seerr-team/seerr v3.4.1) has no
      # trusted-header-SSO or OIDC support despite Authelia's own doc
      # claiming otherwise — `network.trustProxy` is unrelated to auth.
      services.nginx.virtualHosts."seerr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://${ip}:5055";
        forwardAuth = true;
      };
    };
}
