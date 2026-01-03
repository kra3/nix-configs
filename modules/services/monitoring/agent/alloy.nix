{ config, ... }:
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
      }
    }
  '';
}
