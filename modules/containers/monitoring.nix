{
  containers.monitoring = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.50.1";
    localAddress = "10.0.50.2";
    config = {
      imports = [
        ../nix.nix
        ../services/monitoring/server
      ];

      networking.hostName = "monitoring";
      networking.enableIPv6 = false;
      networking.firewall.allowedTCPPorts = [
        3001
        3100
        9090
      ];
      time.timeZone = "UTC";
      system.stateVersion = "25.05";
    };
    bindMounts = {
      "/run/secrets/monitoring.grafana.admin.user" = {
        hostPath = "/run/secrets/monitoring.grafana.admin.user";
        isReadOnly = true;
      };
      "/run/secrets/monitoring.grafana.admin.password" = {
        hostPath = "/run/secrets/monitoring.grafana.admin.password";
        isReadOnly = true;
      };
    };
  };
}
