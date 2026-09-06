{
  flake.nixosModules.containers-media-mgmt-sabnzbd =
    {
      config,
      flakeLib,
      flakeModules,
      ...
    }:
    let
      network = config.virtualisation.quadlet.networks.media-mgmt;
      ip = config.vars.network.podmanAddresses.sabnzbd;
    in
    {
      imports = [ flakeModules.nixos.services-media-acquisition-sabnzbd ];

      sops.secrets."media.sabnzbd.api_key" = { };
      sops.secrets."media.sabnzbd.nzb_key" = { };

      sops.templates."media.sabnzbd.env" = {
        owner = "root";
        group = "media";
        mode = "0440";
        content = ''
          SABNZBD__API_KEY=${config.sops.placeholder."media.sabnzbd.api_key"}
          SABNZBD__NZB_KEY=${config.sops.placeholder."media.sabnzbd.nzb_key"}
        '';
      };

      virtualisation.quadlet.containers.sabnzbd = {
        containerConfig = {
          # Pinned to its current dynamically-assigned IP — see
          # media-mgmt/radarr.nix for why. IP centralized in vars.nix
          # (podmanAddresses.sabnzbd).
          networks = [ "${network.ref}:ip=${ip}" ];
          volumes = [
            "/srv/appdata/media-mgmt/sabnzbd:/config"
            "/srv/media/downloads:/data/downloads"
          ];
          # Floored above the formula: this window likely didn't catch an active extraction.
          memory = "512m";
          podmanArgs = [ "--cpus=1" ];
        };
      }
      // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

      services.nginx.virtualHosts."sabnzbd.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://${ip}:8080";
        forwardAuth = true;
      };
    };
}
