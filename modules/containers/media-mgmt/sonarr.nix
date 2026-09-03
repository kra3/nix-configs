{
  flake.nixosModules.containers-media-mgmt-sonarr = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
    ip = config.vars.network.podmanAddresses.sonarr;
  in
  {
    imports = [ flakeModules.nixos.services-media-acquisition-sonarr ];

    sops.secrets."media.sonarr.api_key" = { };

    sops.templates."media.sonarr.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = "SONARR__API_KEY=${config.sops.placeholder."media.sonarr.api_key"}";
    };

    virtualisation.quadlet.containers.sonarr = {
      containerConfig = {
        # Pinned to its current dynamically-assigned IP — see
        # media-mgmt/radarr.nix for why. IP centralized in vars.nix
        # (podmanAddresses.sonarr).
        networks = [ "${network.ref}:ip=${ip}" ];
        volumes = [
          "/srv/appdata/media-mgmt/sonarr:/config"
          "/srv/media:/data"
        ];
        # Sized from ~21h process-exporter peak + safety margin.
        memory = "640m";
        podmanArgs = [ "--cpus=1" ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    services.nginx.virtualHosts."sonarr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://${ip}:8989";
      forwardAuth = true;
    };
  };
}
