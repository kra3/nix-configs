{
  users.users.nginx.extraGroups = [ "acme" ];

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    commonHttpConfig = ''
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Forwarded-Host $host;
      proxy_set_header X-Forwarded-Port $server_port;
    '';

    virtualHosts."karunagath.in" = {
      enableACME = true;
      forceSSL = true;
      extraConfig = ''
        allow 192.168.1.0/24;
        allow 127.0.0.1;
        deny all;
      '';
      locations."/" = {
        return = "404";
      };
    };

    virtualHosts."*.karunagath.in" = {
      useACMEHost = "karunagath.in";
      forceSSL = true;
      extraConfig = ''
        allow 192.168.1.0/24;
        allow 127.0.0.1;
        deny all;
      '';
      locations."/" = {
        return = "404";
      };
    };


  };

  networking.firewall.interfaces.enp2s0.allowedTCPPorts = [
    443
  ];
}
