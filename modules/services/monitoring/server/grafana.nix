{ config, lib, ... }:
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
            disableDeletion = false;
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
    "grafana-dashboards/nginx.json".source = ./dashboards/nginx.json;
    "grafana-dashboards/unbound.json".source = ./dashboards/unbound.json;
    "grafana-dashboards/zfs.json".source = ./dashboards/zfs.json;
    "grafana-dashboards/logs-overview.json".source = ./dashboards/logs-overview.json;
    "grafana-dashboards/system-monitor.json".source = ./dashboards/system-monitor.json;
    "grafana-dashboards/system-overview.json".source = ./dashboards/system-overview.json;
    "grafana-dashboards/frigate.json".source = ./dashboards/frigate.json;
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/grafana 0750 grafana grafana - -"
    "d /var/lib/grafana/data 0750 grafana grafana - -"
    "d /var/lib/grafana/data/log 0750 grafana grafana - -"
  ];

  services.logrotate.settings.grafana = {
    files = [
      "/var/lib/grafana/data/log/*.log"
    ];
    rotate = 1;
    frequency = "hourly";
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    copytruncate = true;
    su = "grafana grafana";
  };

  environment.etc."alloy/grafana.alloy".text = ''
    loki.source.file "grafana" {
      targets = [
        {
          __path__ = "/var/lib/grafana/data/log/grafana.log",
          job = "grafana",
          host = "${config.networking.hostName}",
          role = "${if config.boot.isContainer then "container" else "host"}",
        },
      ]
      forward_to = [loki.write.default.receiver]
    }
  '';
}
