{
  flake.nixosModules.containers-media-mgmt-unpackerr = { config, lib, flakeLib, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
  in
  {
    sops.templates."media.unpackerr.env" = {
      owner = "root";
      group = "media";
      mode = "0440";
      content = ''
        UN_SONARR_0_URL=http://sonarr:8989
        UN_SONARR_0_API_KEY=${config.sops.placeholder."media.sonarr.api_key"}
        UN_SONARR_0_PATHS_0=/data
        UN_SONARR_0_PROTOCOLS=torrent,TorrentDownloadProtocol
        UN_RADARR_0_URL=http://radarr:7878
        UN_RADARR_0_API_KEY=${config.sops.placeholder."media.radarr.api_key"}
        UN_RADARR_0_PATHS_0=/data
        UN_RADARR_0_PROTOCOLS=torrent,TorrentDownloadProtocol
        UN_LIDARR_0_URL=http://lidarr:8686
        UN_LIDARR_0_API_KEY=${config.sops.placeholder."media.lidarr.api_key"}
        UN_LIDARR_0_PATHS_0=/data
        UN_LIDARR_0_PROTOCOLS=torrent,TorrentDownloadProtocol
        UN_WEBSERVER_METRICS=true
        UN_WEBSERVER_LISTEN_ADDR=0.0.0.0:5656
      '';
    };
  
    virtualisation.quadlet.containers.unpackerr = {
      containerConfig = {
        image = "ghcr.io/unpackerr/unpackerr:0.15.2";
        publishPorts = [ "127.0.0.1:5656:5656" ];
        networks = [ network.ref ];
        logDriver = "journald";
        user = "1000:2000";
        environments = {
          PUID = "1000";
          PGID = "2000";
          TZ = "UTC";
        };
        environmentFiles = [ config.sops.templates."media.unpackerr.env".path ];
        volumes = [
          "/srv/appdata/media-mgmt/unpackerr:/config"
          "/srv/media:/data"
        ];
      }
      // flakeLib.quadlet.mkHealthCheck {
        port = 5656;
        path = "api/v1/health";
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };
  
    environment.etc."alloy/unpackerr.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "unpackerr";
      hostName = config.networking.hostName;
    };
  };
}
