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

    # Split-auth vhost: AIOStreams mounts its human dashboard at "/" and
    # "/api/", but serves the Stremio client itself (manifest/stream/catalog)
    # under "/stremio/", "/builtins/", "/chilllink/", "/seanime/",
    # "/community/", "/blocklist/", "/static/" — a browser-cookie forward-auth
    # can only gate the former; the TV's Stremio app can't complete an
    # Authelia redirect, so those paths stay CIDR-only, same as everything
    # else in nginxAllowCidrs. mkProxyVhost can't express this per-location
    # split, so this vhost is built by hand from its shared pieces.
    services.nginx.virtualHosts."aiostreams.${config.vars.acme.domain}" = {
      useACMEHost = config.vars.acme.domain;
      forceSSL = true;
      extraConfig = flakeLib.nginx.mkAllowBlock config.vars.network.nginxAllowCidrs;
      locations =
        let
          upstream = "http://${ip}:3000";
          public = {
            proxyPass = upstream;
          };
          authed = {
            proxyPass = upstream;
            extraConfig = flakeLib.nginx.forwardAuthLocationConfig;
          };
        in
        {
          "/" = authed;
          "/api/" = authed;
          "/stremio" = public;
          "/builtins" = public;
          "/chilllink" = public;
          "/seanime" = public;
          "/community" = public;
          "/blocklist" = public;
          "/static" = public;
          "/internal/authelia/authz" = flakeLib.nginx.autheliaAuthzLocation;
        };
    };
  };
}
