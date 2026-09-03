{
  flake.nixosModules.containers-media-mgmt-prowlarr = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
    ip = config.vars.network.podmanAddresses.prowlarr;
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
        # media-mgmt/radarr.nix for why. IP centralized in vars.nix
        # (podmanAddresses.prowlarr).
        networks = [ "${network.ref}:ip=${ip}" ];
        volumes = [
          "/srv/appdata/media-mgmt/prowlarr:/config"
        ];
        # Sized from ~21h process-exporter peak + safety margin.
        memory = "640Mi";
        podmanArgs = [ "--cpus=1" ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    services.nginx.virtualHosts."prowlarr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://${ip}:9696";
      forwardAuth = true;
    };
  };
}
