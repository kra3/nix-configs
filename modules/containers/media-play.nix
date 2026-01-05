{
  networking.firewall.interfaces = {
    ve-media-play = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };
  };

  containers.media-play = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.50.5";
    localAddress = "10.0.50.6";
    config = {
      imports = [
        ../nix.nix
        ../services/media/players/server
      ];

      networking = {
        hostName = "media-play";
        enableIPv6 = false;
        defaultGateway = "10.0.50.5";
        nameservers = [ "192.168.1.10" ];
        useHostResolvConf = false;
      };
      time.timeZone = "UTC";
      system.stateVersion = "25.05";
    };
    bindMounts = {
      "/dev/dri" = {
        hostPath = "/dev/dri";
        isReadOnly = false;
      };
      "/data" = {
        hostPath = "/srv/media";
        isReadOnly = false;
      };
      "/var/lib/jellyfin" = {
        hostPath = "/srv/appdata/media-play/jellyfin";
        isReadOnly = false;
      };
    };
    allowedDevices = [
      {
        node = "/dev/dri/card0";
        modifier = "rw";
      }
      {
        node = "/dev/dri/renderD128";
        modifier = "rw";
      }
    ];
  };
}
