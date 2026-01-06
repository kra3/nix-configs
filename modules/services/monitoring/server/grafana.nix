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
            url = "http://10.0.50.2:9090";
            isDefault = true;
          }
          {
            name = "Loki";
            type = "loki";
            access = "proxy";
            url = "http://10.0.50.2:3100";
          }
        ];
      };
      dashboards.settings = {
        apiVersion = 1;
        providers = [
          {
            name = "default";
            orgId = 1;
            folder = "Sutala";
            type = "file";
            disableDeletion = true;
            editable = false;
            options.path = "/etc/grafana-dashboards";
          }
        ];
      };
    };
  };

  systemd.services.grafana = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  environment.etc = {
    "grafana-dashboards/services-overview.json".source = ./dashboards/services-overview.json;
    "grafana-dashboards/system-metrics.json".source = ./dashboards/system-metrics.json;
    "grafana-dashboards/node.json".source = ./dashboards/node.json;
    "grafana-dashboards/nginx.json".source = ./dashboards/nginx.json;
    "grafana-dashboards/unbound.json".source = ./dashboards/unbound.json;
    "grafana-dashboards/zfs.json".source = ./dashboards/zfs.json;
  };
}
