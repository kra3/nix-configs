{
  flake.nixosModules.containers-media-mgmt-aiostreams = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
    ip = config.vars.network.podmanAddresses.aiostreams;
  in
  {
    imports = [ flakeModules.nixos.services-media-streaming-aiostreams ];

    sops.secrets."media.aiostreams.secret_key" = { };
    sops.secrets."media.aiostreams.auth" = { };

    sops.templates."media.aiostreams.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = ''
        SECRET_KEY=${config.sops.placeholder."media.aiostreams.secret_key"}
        AIOSTREAMS_AUTH=${config.sops.placeholder."media.aiostreams.auth"}
      '';
    };

    virtualisation.quadlet.containers.aiostreams = {
      containerConfig = {
        # Pinned to its current dynamically-assigned IP — see
        # media-mgmt/radarr.nix for why. IP centralized in vars.nix
        # (podmanAddresses.aiostreams).
        networks = [ "${network.ref}:ip=${ip}" ];
        volumes = [ "/srv/appdata/media-mgmt/aiostreams:/app/data" ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    # No Authelia forward-auth: the Stremio app on the TV hits this same
    # host for stream URLs and can't complete a browser OIDC redirect.
    # Access is gated by the LAN/Tailscale CIDR allowlist plus AIOStreams'
    # own operator auth (AIOSTREAMS_AUTH) on its dashboard/config pages.
    services.nginx.virtualHosts."aiostreams.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://${ip}:3000";
    };
  };
}
