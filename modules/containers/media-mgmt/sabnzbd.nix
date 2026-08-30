{
  flake.nixosModules.containers-media-mgmt-sabnzbd = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
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
        # media-mgmt/radarr.nix for why.
        networks = [ "${network.ref}:ip=10.3.1.12" ];
        volumes = [
          "/srv/appdata/media-mgmt/sabnzbd:/config"
          "/srv/media/downloads:/data/downloads"
        ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    services.nginx.virtualHosts."sabnzbd.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://10.3.1.12:8080";
      forwardAuth = true;
    };
  };
}
