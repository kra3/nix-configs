{
  flake.nixosModules.containers-media-mgmt-sonarr = { config, lib, flakeLib, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
  in
  {
    sops.secrets."media.sonarr.api_key" = { };

    sops.templates."media.sonarr.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = "SONARR__API_KEY=${config.sops.placeholder."media.sonarr.api_key"}";
    };

    virtualisation.quadlet.containers.sonarr = {
      containerConfig = {
        image = "lscr.io/linuxserver/sonarr:4.0.19.2979-ls321";
        publishPorts = [ "127.0.0.1:8989:8989" ];
        networks = [ network.ref ];
        logDriver = "journald";
        environments = {
          PUID = "1000";
          PGID = "2000";
          TZ = "UTC";
        };
        environmentFiles = [ config.sops.templates."media.sonarr.env".path ];
        volumes = [
          "/srv/appdata/media-mgmt/sonarr:/config"
          "/srv/media:/data"
        ];
      } // flakeLib.quadlet.mkHealthCheck { port = 8989; };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };

    environment.etc."alloy/sonarr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "sonarr";
      hostName = config.networking.hostName;
    };

    services.nginx.virtualHosts."sonarr.${config.vars.acme.domain}" = flakeLib.nginx.mkProxyVhost {
      domain = config.vars.acme.domain;
      cidrs = config.vars.network.nginxAllowCidrs;
      upstream = "http://127.0.0.1:8989";
    };
  };
}
