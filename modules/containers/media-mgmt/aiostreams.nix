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
    sops.secrets."media.aiostreams.oidc_client_secret" = { };

    sops.templates."media.aiostreams.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = ''
        SECRET_KEY=${config.sops.placeholder."media.aiostreams.secret_key"}
        AIOSTREAMS_AUTH=${config.sops.placeholder."media.aiostreams.auth"}
        AIOSTREAMS_OIDC_CLIENT_SECRET=${config.sops.placeholder."media.aiostreams.oidc_client_secret"}
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

    # No Authelia forward-auth: AIOStreams has native OIDC support scoped to
    # its own dashboard/config-page login (wired against Authelia in
    # authelia.nix), which it applies without ever affecting the Stremio
    # addon paths the TV app hits directly — unlike nginx-layer forward-auth,
    # which would have needed a per-location split to avoid gating those too.
    services.nginx.virtualHosts."aiostreams.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://${ip}:3000";
    };
  };
}
