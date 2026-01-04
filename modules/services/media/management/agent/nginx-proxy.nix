{
  services.nginx.virtualHosts."radarr.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = ''
      allow 192.168.1.0/24;
      allow 127.0.0.1;
      deny all;
    '';
    locations."/" = {
      proxyPass = "http://10.0.50.4:7878";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."sonarr.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = ''
      allow 192.168.1.0/24;
      allow 127.0.0.1;
      deny all;
    '';
    locations."/" = {
      proxyPass = "http://10.0.50.4:8989";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."prowlarr.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = ''
      allow 192.168.1.0/24;
      allow 127.0.0.1;
      deny all;
    '';
    locations."/" = {
      proxyPass = "http://10.0.50.4:9696";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."sabnzbd.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = ''
      allow 192.168.1.0/24;
      allow 127.0.0.1;
      deny all;
    '';
    locations."/" = {
      proxyPass = "http://10.0.50.4:8080";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."bazarr.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = ''
      allow 192.168.1.0/24;
      allow 127.0.0.1;
      deny all;
    '';
    locations."/" = {
      proxyPass = "http://10.0.50.4:6767";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."lidarr.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = ''
      allow 192.168.1.0/24;
      allow 127.0.0.1;
      deny all;
    '';
    locations."/" = {
      proxyPass = "http://10.0.50.4:8686";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."jellyseerr.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = ''
      allow 192.168.1.0/24;
      allow 127.0.0.1;
      deny all;
    '';
    locations."/" = {
      proxyPass = "http://10.0.50.4:5055";
      proxyWebsockets = true;
    };
  };
}
