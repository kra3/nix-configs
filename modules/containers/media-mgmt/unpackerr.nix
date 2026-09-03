{
  flake.nixosModules.containers-media-mgmt-unpackerr = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.media-mgmt;
  in
  {
    imports = [ flakeModules.nixos.services-media-acquisition-unpackerr ];

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
        networks = [ network.ref ];
        volumes = [
          "/srv/appdata/media-mgmt/unpackerr:/config"
          "/srv/media:/data"
        ];
        # Floored above the formula: this window likely didn't catch an active extraction.
        memory = "512m";
        podmanArgs = [ "--cpus=1" ];
      };
    } // flakeLib.quadlet.mkNetworkDeps { networkServices = [ "media-mgmt-network.service" ]; };
  };
}
