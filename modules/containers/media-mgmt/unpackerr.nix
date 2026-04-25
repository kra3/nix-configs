{ config, lib, ... }:
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
      healthCmd = "wget -qO- http://localhost:5656/api/v1/health";
      healthOnFailure = "none";
      healthInterval = "30s";
      healthTimeout = "10s";
      healthRetries = 3;
      healthStartPeriod = "30s";
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
    };
    unitConfig = {
      After = [ "media-mgmt-network.service" ];
      Requires = [ "media-mgmt-network.service" ];
    };
    serviceConfig.Restart = "always";
  };

  environment.etc."alloy/unpackerr.alloy".text = ''
    loki.source.journal "unpackerr" {
      matches = "_SYSTEMD_UNIT=unpackerr.service"
      labels = {
        job = "unpackerr",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';
}
