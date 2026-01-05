{
  services.nginx.virtualHosts."jellyfin.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = ''
      allow 192.168.1.0/24;
      allow 127.0.0.1;
      deny all;
    '';
    locations."/" = {
      proxyPass = "http://10.0.50.6:8096";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."navidrome.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = ''
      allow 192.168.1.0/24;
      allow 127.0.0.1;
      deny all;
    '';
    locations."/" = {
      proxyPass = "http://10.0.50.6:4533";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."mass.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = ''
      allow 192.168.1.0/24;
      allow 127.0.0.1;
      deny all;
    '';
    locations."/" = {
      proxyPass = "http://10.0.50.6:8095";
      proxyWebsockets = true;
    };
  };
}
