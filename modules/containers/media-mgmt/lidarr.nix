{
  flake.nixosModules.containers-media-mgmt-lidarr =
    {
      config,
      flakeLib,
      flakeModules,
      pkgs,
      ...
    }:
    let
      network = config.virtualisation.quadlet.networks.media-mgmt;
      ip = config.vars.network.podmanAddresses.lidarr;

      # Lidarr's Custom Script (On Track Retag) runs inside this container's
      # own namespace, so it can't reach the host's beet install directly --
      # this just curls services-media-lidarr-beets-webhook on the host,
      # which does the real path translation + beet invoke. Shebang points at
      # /bin/sh since that's what exists inside Lidarr's own image, not a nix
      # store path.
      retagTrigger = pkgs.writeTextFile {
        name = "lidarr-retag-trigger.sh";
        executable = true;
        text = ''
          #!/bin/sh
          set -eu
          [ "''${lidarr_eventtype:-}" = "Test" ] && exit 0
          [ "''${lidarr_eventtype:-}" != "TrackRetag" ] && exit 0
          wget -qO- --post-data="path=$lidarr_trackfile_path" "http://host.containers.internal:8942/retag"
        '';
      };
    in
    {
      imports = [ flakeModules.nixos.services-media-acquisition-lidarr ];

      sops.secrets."media.lidarr.api_key" = { };

      sops.templates."media.lidarr.env" = {
        owner = "root";
        group = "media";
        mode = "0440";
        content = "LIDARR__API_KEY=${config.sops.placeholder."media.lidarr.api_key"}";
      };

      virtualisation.quadlet.containers.lidarr = {
        containerConfig = {
          # Pinned to its current dynamically-assigned IP — see
          # media-mgmt/radarr.nix for why. IP centralized in vars.nix
          # (podmanAddresses.lidarr).
          networks = [ "${network.ref}:ip=${ip}" ];
          volumes = [
            "/srv/appdata/media-mgmt/lidarr:/config"
            "/srv/media:/data"
            "${retagTrigger}:/scripts/lidarr-retag-trigger.sh:ro"
          ];
          # Sized from ~21h process-exporter peak + safety margin.
          memory = "640m";
          podmanArgs = [ "--cpus=1" ];
        };
      }
      // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

      services.nginx.virtualHosts."lidarr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://${ip}:8686";
        forwardAuth = true;
      };
    };
}
