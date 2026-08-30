{
  flake.nixosModules.containers-media-mgmt-sonarr = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
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
        # media-mgmt/radarr.nix for why.
        networks = [ "${network.ref}:ip=10.3.1.10" ];
        volumes = [
          "/srv/appdata/media-mgmt/sonarr:/config"
          "/srv/media:/data"
        ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    services.nginx.virtualHosts."sonarr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://10.3.1.10:8989";
      forwardAuth = true;
    };
  };
}
