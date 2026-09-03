{
  # Standalone secondary DNS resolver for hosts/surasa -- plain port-53
  # AdGuard Home + Unbound, no TLS/nginx/ACME and no sutala container-name
  # rewrites (those are sutala-only concerns, see services-dns-adguard).
  # Filter-list subscriptions are shared with sutala's instance via
  # flakeLib.adguard-filters (modules/lib/adguard-filters.nix) so both
  # block the same things.
  flake.nixosModules.services-dns-rpi-secondary =
  { config, lib, pkgs, flakeLib, ... }:
  let
    net = config.vars.network;
  in
  {
    services.unbound = {
      enable = true;
      settings = {
        server = {
          interface = [ "127.0.0.1" ];
          access-control = [ "127.0.0.0/8 allow" ];
          port = 5335;
          do-daemonize = false;
          prefetch = "yes";
          edns-buffer-size = 1232;
          harden-glue = "yes";
          harden-dnssec-stripped = "yes";
          use-caps-for-id = "yes";
          hide-identity = "yes";
          hide-version = "yes";
          minimal-responses = "yes";
          deny-any = "yes";
          harden-referral-path = "yes";
          harden-algo-downgrade = "yes";
          do-not-query-localhost = "yes";
        };
        remote-control.control-enable = true;
        forward-zone = [
          {
            name = ".";
            forward-tls-upstream = true;
            forward-addr = [
              "1.1.1.1@853#family.cloudflare-dns.com"
              "9.9.9.11@853#dns11.quad9.net"
            ];
          }
        ];
      };
    };

    users.groups.adguardhome = { };
    users.users.adguardhome = {
      isSystemUser = true;
      group = "adguardhome";
      home = "/var/lib/AdGuardHome";
      createHome = false;
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/AdGuardHome 0750 adguardhome adguardhome - -"
    ];

    systemd.services.adguardhome.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "adguardhome";
      Group = "adguardhome";
      LoadCredential = [
        "password:${config.sops.secrets."dns.adguard.password".path}"
        "username:${config.sops.secrets."dns.adguard.username".path}"
      ];
    };

    # Same admin login as sutala's AdGuard instance -- reuses the exact same
    # dns.adguard.username/password sops keys (not a copy), so both
    # instances decrypt the same secret independently once this host is a
    # sops recipient (see the TODO in hosts/surasa/configuration.nix).
    sops.secrets."dns.adguard.password" = {
      owner = "adguardhome";
      group = "adguardhome";
      mode = "0440";
    };
    sops.secrets."dns.adguard.username" = {
      owner = "adguardhome";
      group = "adguardhome";
      mode = "0440";
    };

    systemd.services.adguardhome.preStart =
      let
        setupScript = pkgs.writeShellScript "adguard-setup" ''
          set -euo pipefail

          if [ -f "$STATE_DIRECTORY/AdGuardHome.yaml" ]; then
            # Read credentials from systemd credential directory (secure, not visible in ps)
            PASSWORD=$(${pkgs.coreutils}/bin/cat "''${CREDENTIALS_DIRECTORY}/password" | ${pkgs.coreutils}/bin/tr -d '\n')
            USERNAME=$(${pkgs.coreutils}/bin/cat "''${CREDENTIALS_DIRECTORY}/username" | ${pkgs.coreutils}/bin/tr -d '\n')

            # Create temporary sed script to avoid password in command line
            SCRIPT=$(${pkgs.coreutils}/bin/mktemp)
            trap "${pkgs.coreutils}/bin/rm -f $SCRIPT" EXIT

            # Write sed commands to temp file (not visible in ps)
            cat > "$SCRIPT" <<EOF
          s|__SOPS_DNS_ADGUARD_PASSWORD__|$PASSWORD|
          s|__SOPS_DNS_ADGUARD_USERNAME__|$USERNAME|
          EOF

            # Execute sed with script file (no secrets in command line)
            ${pkgs.gnused}/bin/sed -i -f "$SCRIPT" "$STATE_DIRECTORY/AdGuardHome.yaml"
          fi
        '';
      in
      lib.mkAfter (toString setupScript);

    services.adguardhome = {
      enable = true;
      mutableSettings = false;
      allowDHCP = false;
      host = net.lanIp;
      port = 3000;
      openFirewall = false;

      settings = {
        schema_version = config.services.adguardhome.package.schema_version;

        dns = {
          bind_hosts = [
            "127.0.0.1"
            net.lanIp
          ];
          port = 53;
          upstream_dns = [ "127.0.0.1:5335" ];
          upstream_mode = "load_balance";
          bootstrap_dns = [
            "9.9.9.10"
            "149.112.112.10"
          ];
          cache_size = 4194304;
          enable_dnssec = true;
        };

        filtering = {
          filtering_enabled = true;
          protection_enabled = true;
        };

        filters = flakeLib.adguard-filters;

        # Substituted from sops at runtime by the preStart script above --
        # these placeholder strings, not real values, are what land in the
        # Nix store.
        users = [
          {
            name = "__SOPS_DNS_ADGUARD_USERNAME__";
            password = "__SOPS_DNS_ADGUARD_PASSWORD__";
          }
        ];
      };
    };

    networking.firewall.interfaces.${net.lanIf} = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };
  };
}
