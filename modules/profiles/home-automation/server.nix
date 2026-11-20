{
  flake.nixosModules.profiles-home-automation-server =
    { config, flakeModules, ... }:
    let
      c = config.vars.network.containers;
      p = config.vars.network.podmanSubnets;
      ha = c.homeAuto.localAddress;
      haNet = p.homeAuto;
      lan = config.vars.network.lanCidr;
    in
    {
      imports = [
        flakeModules.nixos.containers-home-auto
        flakeModules.nixos.containers-home-auto-home-assistant-default
        flakeModules.nixos.containers-home-auto-otbr-default
        flakeModules.nixos.containers-home-auto-matter-server-default
        flakeModules.nixos.services-postgres
      ];

      # The db password is still set centrally by postgresql-set-passwords in services/postgres.nix.
      services.postgresql.ensureDatabases = [ "hass" ];
      services.postgresql.ensureUsers = [
        {
          name = "hass";
          ensureDBOwnership = true;
          ensureClauses = {
            login = true;
          };
        }
      ];

      networking.nat.forwardPorts = [
        {
          sourcePort = 1883;
          destination = "${ha}:1883";
          proto = "tcp";
        }
        {
          sourcePort = 8555;
          destination = "${ha}:8555";
          proto = "tcp";
        }
        {
          sourcePort = 8555;
          destination = "${ha}:8555";
          proto = "udp";
        }
      ];

      networking.firewall.extraForwardRules = ''
        # 6. HA pod → home-auto: HA talks to MQTT + Frigate
        ip saddr ${haNet} ip daddr ${ha} tcp dport { 1883, 5000 } accept
        # 6a. home-auto → HA pod: MQTT return traffic (Fixes 'Connection Reset')
        ip saddr ${ha} ip daddr ${haNet} tcp sport 1883 accept
        # 7. home-auto → HA pod: Frigate notifications / automations
        ip saddr ${ha} ip daddr ${haNet} tcp dport 8123 accept
        # 10. LAN → home-auto: DNAT for MQTT + WebRTC
        ip saddr ${lan} ip daddr ${ha} tcp dport { 1883, 8555 } accept
        ip saddr ${lan} ip daddr ${ha} udp dport 8555 accept
        # 11. Podman subnets → internet (outbound NAT)
        ip saddr ${haNet} accept comment "home-auto pods outbound"
      '';
    };
}
