{
  services.grafana = {
    enable = true;
    settings = {
      security = {
        admin_user = "$__file{/run/secrets/monitoring.grafana.admin.user}";
        admin_password = "$__file{/run/secrets/monitoring.grafana.admin.password}";
      };
      server = {
        http_addr = "10.0.50.2";
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

  systemd.services.grafana = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}
