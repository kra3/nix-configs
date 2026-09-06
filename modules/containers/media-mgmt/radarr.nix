{
  flake.nixosModules.containers-media-mgmt-radarr =
    {
      config,
      flakeLib,
      flakeModules,
      ...
    }:
    let
      network = config.virtualisation.quadlet.networks.media-mgmt;
      ip = config.vars.network.podmanAddresses.radarr;
    in
    {
      imports = [ flakeModules.nixos.services-media-acquisition-radarr ];

      sops.secrets."media.radarr.api_key" = { };

      sops.templates."media.radarr.env" = {
        owner = "root";
        group = "media";
        mode = "0440";
        content = "RADARR__API_KEY=${config.sops.placeholder."media.radarr.api_key"}";
      };

      virtualisation.quadlet.containers.radarr = {
        containerConfig = {
          # Pinned to its current dynamically-assigned IP, so nginx can reach
          # it directly on the bridge instead of via a host-loopback publish
          # (see services/media/acquisition/radarr.nix) without disturbing
          # whatever already resolves/references this container's address.
          # IP centralized in vars.nix (podmanAddresses.radarr).
          networks = [ "${network.ref}:ip=${ip}" ];
          volumes = [
            "/srv/appdata/media-mgmt/radarr:/config"
            "/srv/media:/data"
          ];
          # Sized from ~21h process-exporter peak + safety margin.
          memory = "640m";
          podmanArgs = [ "--cpus=1" ];
        };
      }
      // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

      services.nginx.virtualHosts."radarr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://${ip}:7878";
        forwardAuth = true;
      };
    };
}
