{
  flake.nixosModules.containers-media-mgmt-slskd =
    {
      config,
      pkgs,
      flakeLib,
      flakeModules,
      ...
    }:
    let
      network = config.virtualisation.quadlet.networks.media-mgmt;
      ip = config.vars.network.podmanAddresses.slskd;
      slskdYaml = pkgs.writeText "slskd.yml" ''
        transfers:
          upload:
            speed_limit: 25000
          groups:
            leechers:
              thresholds:
                files: 1
                directories: 1
              upload:
                speed_limit: 3000
      '';
    in
    {
      imports = [ flakeModules.nixos.services-media-acquisition-slskd ];

      sops.secrets."media.slskd.soulseek_username" = { };
      sops.secrets."media.slskd.soulseek_password" = { };
      sops.secrets."media.slskd.web_username" = { };
      sops.secrets."media.slskd.web_password" = { };
      sops.secrets."media.slskd.api_key" = { };

      sops.templates."media.slskd.env" = {
        owner = "root";
        group = "media";
        mode = "0440";
        content = ''
          SLSKD_SLSK_USERNAME=${config.sops.placeholder."media.slskd.soulseek_username"}
          SLSKD_SLSK_PASSWORD=${config.sops.placeholder."media.slskd.soulseek_password"}
          SLSKD_USERNAME=${config.sops.placeholder."media.slskd.web_username"}
          SLSKD_PASSWORD=${config.sops.placeholder."media.slskd.web_password"}
          SLSKD_API_KEY=${config.sops.placeholder."media.slskd.api_key"}
        '';
      };

      virtualisation.quadlet.containers.slskd = {
        containerConfig = {
          # Pinned to its current dynamically-assigned IP — see
          # media-mgmt/radarr.nix for why. IP centralized in vars.nix
          # (podmanAddresses.slskd).
          networks = [ "${network.ref}:ip=${ip}" ];
          volumes = [
            "/srv/appdata/media-mgmt/slskd:/app"
            "/srv/media/downloads/slskd:/data/downloads/slskd"
            # Shared read-only so slskd can upload to the Soulseek network —
            # reciprocity matters there for download speed/queue priority.
            "/srv/media/library/music/Western:/music/Western:ro"
            "/srv/media/library/music/Indian:/music/Indian:ro"
            "${slskdYaml}:/app/slskd.yml:ro"
          ];
          environments = {
            SLSKD_DOWNLOADS_DIR = "/data/downloads/slskd/complete";
            SLSKD_INCOMPLETE_DIR = "/data/downloads/slskd/incomplete";
            SLSKD_SHARED_DIR = "/music/Western;/music/Indian";
            SLSKD_METRICS = "true";
            SLSKD_METRICS_NO_AUTH = "true";
          };
          memory = "512m";
          podmanArgs = [ "--cpus=1" ];
        };
      }
      // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

      # Soulseek P2P listen port must be reachable from the router's forward —
      # traffic arrives on the LAN interface, unlike the bridge-only ports
      # used by everything else in this stack.
      networking.firewall.interfaces.${config.vars.network.lanIf}.allowedTCPPorts = [ 50300 ];

      services.nginx.virtualHosts."slskd.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
        domain = config.vars.acme.domain;
        cidrs = config.vars.network.nginxAllowCidrs;
        upstream = "http://${ip}:5030";
        forwardAuth = true;
      };
    };
}
