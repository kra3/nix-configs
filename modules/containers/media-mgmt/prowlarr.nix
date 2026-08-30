{
  flake.nixosModules.containers-media-mgmt-prowlarr = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
  in
  {
    imports = [ flakeModules.nixos.services-media-acquisition-prowlarr ];

    sops.secrets."media.prowlarr.api_key" = { };

    sops.templates."media.prowlarr.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = "PROWLARR__API_KEY=${config.sops.placeholder."media.prowlarr.api_key"}";
    };

    virtualisation.quadlet.containers.prowlarr = {
      containerConfig = {
        # Pinned to its current dynamically-assigned IP — see
        # media-mgmt/radarr.nix for why.
        networks = [ "${network.ref}:ip=10.3.1.14" ];
        volumes = [
          "/srv/appdata/media-mgmt/prowlarr:/config"
        ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    services.nginx.virtualHosts."prowlarr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://10.3.1.14:9696";
      forwardAuth = true;
    };
  };
}
