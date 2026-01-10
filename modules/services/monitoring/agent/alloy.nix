{ config, ... }:
let
  roleLabel = if config.boot.isContainer then "container" else "host";
in
{
  services.alloy = {
    enable = true;
    extraFlags = [
      "--server.http.listen-addr=127.0.0.1:12345"
    ];
  };

  environment.etc."alloy/config.alloy".text = ''
    loki.write "default" {
      endpoint {
        url = "http://10.0.50.2:3100/loki/api/v1/push"
      }
    }

    loki.source.journal "systemd" {
      forward_to = [loki.write.default.receiver]
      labels = {
        job = "systemd-journal",
        host = "${config.networking.hostName}",
        service_group = "${config.networking.hostName}",
        role = "${roleLabel}",
      }
    }

    loki.source.file "nginx" {
      targets = [
        { __path__ = "/var/log/nginx/*.log" },
      ]
      labels = {
        job = "nginx",
        host = "${config.networking.hostName}",
        service_group = "${config.networking.hostName}",
        role = "${roleLabel}",
      }
      forward_to = [loki.write.default.receiver]
    }

    loki.source.file "app_logs" {
      targets = [
        { __path__ = "/var/lib/*/logs/*.log" },
        { __path__ = "/var/lib/*/log/*.log" },
      ]
      labels = {
        job = "app-logs",
        host = "${config.networking.hostName}",
        service_group = "${config.networking.hostName}",
        role = "${roleLabel}",
      }
      forward_to = [loki.write.default.receiver]
    }

    loki.source.file "adguardhome" {
      targets = [
        { __path__ = "/var/lib/AdGuardHome/data/*.log" },
        { __path__ = "/var/lib/AdGuardHome/data/*.json" },
      ]
      labels = {
        job = "adguardhome",
        host = "${config.networking.hostName}",
        service_group = "${config.networking.hostName}",
        role = "${roleLabel}",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';
}
