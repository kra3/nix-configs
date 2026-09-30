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
          # Temporary: log every invocation's eventtype so we can confirm what
          # On Release Import actually sends before widening the filter below.
          echo "$(date -Iseconds) eventtype=''${lidarr_eventtype:-} path=''${lidarr_trackfile_path:-}" >> /config/retag-debug.log
          [ "''${lidarr_eventtype:-}" != "TrackRetag" ] && exit 0
          wget -qO- --post-data="$lidarr_trackfile_path" "http://host.containers.internal:8942/retag"
        '';
      };

      installTubifarryDeps = pkgs.writeTextFile {
        name = "install-tubifarry-deps.sh";
        executable = true;
        text = ''
          #!/bin/sh
          set -eu
          apk add --no-cache ffmpeg nodejs
        '';
      };
    in
    {
      imports = [ flakeModules.nixos.services-media-acquisition-lidarr ];

      sops.secrets."media.lidarr.api_key" = { };
      sops.secrets."media.lidarr.youtube_cookies" = {
        owner = "root";
        group = "media";
        mode = "0440";
      };

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
            "${installTubifarryDeps}:/custom-cont-init.d/install-tubifarry-deps.sh:ro"
            "${config.sops.secrets."media.lidarr.youtube_cookies".path}:/config/cookies.txt:ro"
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

      # Recycle bin target (set in Lidarr's own UI/API, like its other
      # media-management settings) -- PUID=1000/PGID=2000 matches the container.
      systemd.tmpfiles.rules = [ "d /srv/media/.recycle-bin 0770 1000 2000 - -" ];
    };
}
