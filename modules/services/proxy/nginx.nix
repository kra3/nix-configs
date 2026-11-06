{
  flake.nixosModules.services-proxy-nginx =
    {
      config,
      lib,
      flakeLib,
      ...
    }:
    let
      allowBlock = flakeLib.nginx.mkAllowBlock config.vars.network.nginxAllowCidrs;
    in
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
          proxy_headers_hash_max_size 1024;
          proxy_headers_hash_bucket_size 128;

          # Security headers at http level so every vhost inherits them. nginx drops
          # inherited add_header in any server/location that sets its own add_header;
          # today only the internal Frigate /api/metrics location does (Cache-Control),
          # which Prometheus scrapes, so it is intentionally left without them.
          # If you add add_header elsewhere, repeat these lines there.
          # No repo vhost is embedded in an iframe (no panel_iframe/frame usage), so SAMEORIGIN is safe.
          # Each one only when the upstream didn't already send it (add_header skips empty
          # values), so apps with their own, stricter policy (e.g. HA's no-referrer) win
          # and responses never carry duplicates.
          map $upstream_http_strict_transport_security $sec_hsts {
            "" "max-age=31536000; includeSubDomains";
            default "";
          }
          map $upstream_http_x_content_type_options $sec_nosniff {
            "" "nosniff";
            default "";
          }
          map $upstream_http_referrer_policy $sec_referrer {
            "" "strict-origin-when-cross-origin";
            default "";
          }
          map $upstream_http_x_frame_options $sec_xfo {
            "" "SAMEORIGIN";
            default "";
          }
          add_header Strict-Transport-Security $sec_hsts always;
          add_header X-Content-Type-Options $sec_nosniff always;
          add_header Referrer-Policy $sec_referrer always;
          add_header X-Frame-Options $sec_xfo always;
        '';

        virtualHosts.${config.vars.acme.domain} = {
          enableACME = true;
          forceSSL = true;
          extraConfig = allowBlock;
          locations."/" = {
            return = "404";
          };
        };

        virtualHosts."*.${config.vars.acme.domain}" = {
          useACMEHost = config.vars.acme.domain;
          forceSSL = true;
          extraConfig = allowBlock;
          locations."/" = {
            return = "404";
          };
        };

      };

      systemd.services.nginx.serviceConfig = lib.mkMerge [
        (flakeLib.deployment-hardening.mkServiceSandbox {
          readWritePaths = [ "/var/log/nginx" ];
          capabilities = [ "CAP_NET_BIND_SERVICE" ];
        })
      ];

      networking.firewall.interfaces.${config.vars.network.lanIf}.allowedTCPPorts = [
        443
      ];

      services.logrotate.settings.nginx = {
        files = [
          "/var/log/nginx/*.log"
        ];
        rotate = 1;
        frequency = "hourly";
        compress = true;
        delaycompress = true;
        missingok = true;
        notifempty = true;
        copytruncate = true;
        su = "nginx nginx";
      };

      environment.etc."alloy/config.alloy".text = lib.mkAfter ''
        loki.source.file "nginx" {
          targets = [
            {
              __path__ = "/var/log/nginx/access.log",
              job = "nginx",
              host = "${config.networking.hostName}",
              role = "${if config.boot.isContainer then "container" else "host"}",
            },
            {
              __path__ = "/var/log/nginx/error.log",
              job = "nginx",
              host = "${config.networking.hostName}",
              role = "${if config.boot.isContainer then "container" else "host"}",
            },
          ]
          forward_to = [loki.write.default.receiver]
        }
      '';
    };
}
