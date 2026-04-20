{ config, pkgs, ... }:
let
  network = config.virtualisation.quadlet.networks.home-auto;
in
{
  virtualisation.quadlet.containers.matter-server = {
    containerConfig = {
      image = "ghcr.io/home-assistant-libs/python-matter-server:8.1.0";
      publishPorts = [ "127.0.0.1:5580:5580" ];
      networks = [ "${network.ref}:ip=10.3.2.12" ];
      logDriver = "journald";
      volumes = [
        "/srv/appdata/home-auto/matter-server:/data"
      ];
      addCapabilities = [ "NET_ADMIN" ];
      environments = {
        TZ = "Europe/Stockholm";
      };
    };
    unitConfig = {
      After = [ "home-auto-network.service" "otbr.service" ];
      Requires = [ "home-auto-network.service" ];
    };
    serviceConfig = {
      Restart = "always";
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/appdata/home-auto/matter-server 0750 root root - -"
  ];

  environment.etc."alloy/matter-server.alloy".text = ''
    loki.source.journal "matter_server" {
      matches = "_SYSTEMD_UNIT=matter-server.service"
      labels = {
        job = "matter-server",
        host = "${config.networking.hostName}",
        role = "host",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';
}
