{ config, ... }:
{
  services.grafana = {
    enable = true;
    settings = {
      security = {
        admin_user = "$__file{${config.sops.secrets."monitoring.grafana.admin.user".path}}";
        admin_password = "$__file{${config.sops.secrets."monitoring.grafana.admin.password".path}}";
      };
      server = {
        http_addr = "127.0.0.1";
        http_port = 3001;
        domain = "grafana.karunagath.in";
        root_url = "https://grafana.karunagath.in/";
      };
      analytics.reporting_enabled = false;
    };
    provision = {
      enable = true;
      datasources.settings = {
        apiVersion = 1;
        datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://127.0.0.1:9090";
            isDefault = true;
          }
          {
            name = "Loki";
            type = "loki";
            access = "proxy";
            url = "http://127.0.0.1:3100";
          }
        ];
      };
    };
  };

  sops.secrets."monitoring.grafana.admin.user" = {
    owner = "grafana";
    group = "grafana";
    mode = "0440";
  };
  sops.secrets."monitoring.grafana.admin.password" = {
    owner = "grafana";
    group = "grafana";
    mode = "0440";
  };

  services.nginx.virtualHosts."grafana.karunagath.in" = {
    useACMEHost = "karunagath.in";
    forceSSL = true;
    extraConfig = ''
      allow 192.168.1.0/24;
      allow 127.0.0.1;
      deny all;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:3001";
      proxyWebsockets = true;
    };
  };
}
