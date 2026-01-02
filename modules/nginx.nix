{
  users.users.nginx.extraGroups = [ "acme" ];

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;

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
