{
  services.nginx.virtualHosts."grafana.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = ''
      allow 192.168.1.0/24;
      allow 127.0.0.1;
      deny all;
    '';
    locations."/" = {
      proxyPass = "http://10.0.50.2:3001";
      proxyWebsockets = true;
    };
  };


  sops.secrets."monitoring.grafana.admin.user" = {
    mode = "0444";
  };
  sops.secrets."monitoring.grafana.admin.password" = {
    mode = "0444";
  };
}
