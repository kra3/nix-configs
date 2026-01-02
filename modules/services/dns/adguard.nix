{ config, lib, pkgs, ... }:
let
  cfg = config.vars;
  lanIf = cfg.lanIf;
  lanIp = cfg.lanIp;
  adguardFilters = [
    {
      enabled = true;
      url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
      name = "StevenBlack";
      id = 1;
    }
    {
      enabled = true;
      url = "https://big.oisd.nl/";
      name = "OISD";
      id = 2;
    }
  ];
in
{
  options.vars = {
    lanIf = lib.mkOption {
      type = lib.types.str;
      default = "enp2s0";
    };
    lanIp = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.10";
    };
  };

  config = {
    sops.secrets."dns.adguard.password" = { };
    sops.secrets."dns-static-leases.yaml" = {
      sopsFile = ../../../secrets/dns-static-leases.yaml;
      format = "yaml";
    };

    systemd.services.adguardhome.preStart = lib.mkAfter ''
      if [ -f "$STATE_DIRECTORY/AdGuardHome.yaml" ]; then
        ${lib.getExe pkgs.yaml-merge} \
          "$STATE_DIRECTORY/AdGuardHome.yaml" \
          "${config.sops.secrets."dns-static-leases.yaml".path}" \
          > "$STATE_DIRECTORY/AdGuardHome.yaml.tmp"
        mv "$STATE_DIRECTORY/AdGuardHome.yaml.tmp" "$STATE_DIRECTORY/AdGuardHome.yaml"
      fi
    '';

    services.adguardhome = {
      enable = true;
      mutableSettings = true;
      allowDHCP = true;

      host = "127.0.0.1";
      port = 3000;

      settings = {
        schema_version = config.services.adguardhome.package.schema_version;

        dns = {
          bind_hosts = [ lanIp ];
          port = 53;
          upstream_dns = [ "127.0.0.1:5335" ];
          bootstrap_dns = [ ];
          local_ptr_upstreams = [ "127.0.0.1:5335" ];
        };

        tls = {
          enabled = false;
          allow_unencrypted_doh = true;
        };

        dhcp = {
          enabled = true;
          interface_name = lanIf;
          dhcpv4 = {
            gateway_ip = "192.168.1.1";
            subnet_mask = "255.255.255.0";
            range_start = "192.168.1.100";
            range_end = "192.168.1.199";
            lease_duration = 86400;
          };
        };

        filtering = {
          enabled = true;
        };

        filters = adguardFilters;


        users = [
          {
            name = "kra3";
            password = "$(cat ${config.sops.secrets."dns.adguard.password".path})";
          }
        ];
        auth_attempts = 3;
        block_auth_min = 15;
        theme = "auto";
      };
    };

    services.nginx.virtualHosts."dns.karunagath.in" = {
      useACMEHost = "karunagath.in";
      forceSSL = true;
      extraConfig = ''
        allow 192.168.1.0/24;
        allow 127.0.0.1;
        deny all;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
        proxyWebsockets = true;
      };
      locations."/dns-query" = {
        proxyPass = "http://127.0.0.1:3000";
      };
    };

    networking.firewall.interfaces.${lanIf} = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [
        53
        67
        68
      ];
    };
  };
}
