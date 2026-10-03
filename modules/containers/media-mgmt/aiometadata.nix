{
  flake.nixosModules.containers-media-mgmt-aiometadata =
    {
      config,
      flakeLib,
      flakeModules,
      ...
    }:
    let
      network = config.virtualisation.quadlet.networks.media-mgmt;
      ip = config.vars.network.podmanAddresses.aiometadata;
    in
    {
      imports = [ flakeModules.nixos.services-media-streaming-aiometadata ];

      sops.secrets."media.aiometadata.admin_key" = { };
      sops.secrets."media.aiometadata.oidc_client_secret" = { };
      sops.secrets."media.aiostreams.tmdb_api_key" = { };
      sops.secrets."media.aiostreams.tvdb_api_key" = { };
      sops.secrets."music.fanarttv_api_key" = { };
      sops.secrets."media.aiometadata.rpdb_api_key" = { };
      sops.secrets."media.aiometadata.mdblist_api_key" = { };
      sops.secrets."media.aiometadata.gemini_api_key" = { };
      sops.secrets."db.redis_password" = { };

      sops.templates."media.aiometadata.env" = {
        owner = "root";
        group = "media";
        mode = "0440";
        content = ''
          ADMIN_KEY=${config.sops.placeholder."media.aiometadata.admin_key"}
          OIDC_CLIENT_SECRET=${config.sops.placeholder."media.aiometadata.oidc_client_secret"}
          BUILT_IN_TMDB_API_KEY=${config.sops.placeholder."media.aiostreams.tmdb_api_key"}
          BUILT_IN_TVDB_API_KEY=${config.sops.placeholder."media.aiostreams.tvdb_api_key"}
          BUILT_IN_FANART_API_KEY=${config.sops.placeholder."music.fanarttv_api_key"}
          BUILT_IN_RPDB_API_KEY=${config.sops.placeholder."media.aiometadata.rpdb_api_key"}
          BUILT_IN_MDBLIST_API_KEY=${config.sops.placeholder."media.aiometadata.mdblist_api_key"}
          BUILT_IN_GEMINI_API_KEY=${config.sops.placeholder."media.aiometadata.gemini_api_key"}
          REDIS_URL=redis://:${config.sops.placeholder."db.redis_password"}@host.containers.internal:6379
        '';
      };

      # Rebuildable cache lives outside /srv/appdata so ZFS snapshots skip it.
      systemd.tmpfiles.rules = [
        "d /var/cache/aiometadata 2770 root media - -"
        "d /var/cache/aiometadata/poster-cache 2770 root media - -"
      ];

      virtualisation.quadlet.containers.aiometadata = {
        containerConfig = {
          # Pinned IP (vars.nix podmanAddresses.aiometadata) — see radarr.nix for why.
          networks = [ "${network.ref}:ip=${ip}" ];
          # OIDC discovery calls auth.${domain} directly; route via the bridge gateway.
          addHosts = [ "auth.${config.vars.acme.domain}:10.3.1.1" ];
          volumes = [
            "/srv/appdata/media-mgmt/aiometadata:/app/addon/data"
            "/var/cache/aiometadata/poster-cache:/app/addon/data/poster-cache"
          ];
          memory = "1024m";
          podmanArgs = [ "--cpus=1" ];
        };
      }
      // flakeLib.quadlet.mkNetworkDeps {
        networkServices = [ "media-mgmt-network.service" ];
        extraAfter = [ "redis-default.service" ];
        extraRequires = [ "redis-default.service" ];
      };

      # No forward-auth: Stremio clients fetch manifest/catalog paths directly.
      services.nginx.virtualHosts."aiometadata.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://${ip}:3232";
      };
    };
}
