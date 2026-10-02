{
  flake.nixosModules.containers-media-mgmt-aiostreams =
    {
      config,
      flakeLib,
      flakeModules,
      ...
    }:
    let
      network = config.virtualisation.quadlet.networks.media-mgmt;
      ip = config.vars.network.podmanAddresses.aiostreams;
    in
    {
      imports = [ flakeModules.nixos.services-media-streaming-aiostreams ];

      sops.secrets."media.aiostreams.secret_key" = { };
      sops.secrets."media.aiostreams.auth" = { };
      sops.secrets."media.aiostreams.oidc_client_secret" = { };
      sops.secrets."media.aiostreams.tmdb_access_token" = { };
      sops.secrets."media.aiostreams.tmdb_api_key" = { };
      sops.secrets."media.aiostreams.tvdb_api_key" = { };
      sops.secrets."media.aiostreams.realdebrid_api_key" = { };
      sops.secrets."media.aiostreams.easynews_username" = { };
      sops.secrets."media.aiostreams.easynews_password" = { };
      sops.secrets."media.prowlarr.api_key" = { };

      sops.templates."media.aiostreams.env" = {
        owner = "root";
        group = "media";
        mode = "0440";
        content = ''
          SECRET_KEY=${config.sops.placeholder."media.aiostreams.secret_key"}
          AIOSTREAMS_AUTH=${config.sops.placeholder."media.aiostreams.auth"}
          AIOSTREAMS_OIDC_CLIENT_SECRET=${config.sops.placeholder."media.aiostreams.oidc_client_secret"}
          TMDB_ACCESS_TOKEN=${config.sops.placeholder."media.aiostreams.tmdb_access_token"}
          TMDB_API_KEY=${config.sops.placeholder."media.aiostreams.tmdb_api_key"}
          TVDB_API_KEY=${config.sops.placeholder."media.aiostreams.tvdb_api_key"}
          DEFAULT_SERVICE_CREDENTIALS=realdebrid.apiKey=${
            config.sops.placeholder."media.aiostreams.realdebrid_api_key"
          }\neasynews.username=${
            config.sops.placeholder."media.aiostreams.easynews_username"
          }\neasynews.password=${
            config.sops.placeholder."media.aiostreams.easynews_password"
          }\naiostreams.aiostreamsAuth=${config.sops.placeholder."media.aiostreams.auth"}
          BUILTIN_PROWLARR_API_KEY=${config.sops.placeholder."media.prowlarr.api_key"}
        '';
      };

      virtualisation.quadlet.containers.aiostreams = {
        containerConfig = {
          # Pinned IP (vars.nix podmanAddresses.aiostreams) — see radarr.nix for why.
          networks = [ "${network.ref}:ip=${ip}" ];
          environments.BUILTIN_PROWLARR_URL = "http://${config.vars.network.podmanAddresses.prowlarr}:9696";
          volumes = [ "/srv/appdata/media-mgmt/aiostreams:/app/data" ];
          # Sized from ~21h process-exporter peak + safety margin.
          memory = "2048m";
          podmanArgs = [ "--cpus=1" ];
        };
      }
      // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

      # No forward-auth: AIOStreams' native OIDC (authelia.nix) covers the
      # dashboard without gating the Stremio paths the TV app hits directly.
      services.nginx.virtualHosts."aiostreams.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://${ip}:3000";
      };
    };
}
