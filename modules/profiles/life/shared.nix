{
  # The key makes the module system drop repeat imports, so every life profile can import this.
  flake.nixosModules.profiles-life-shared =
    { config, flakeModules, ... }:
    {
      key = "profiles-life-shared";
      imports = [
        flakeModules.nixos.containers-life-network
        flakeModules.nixos.containers-life-storage
      ];

      users.groups.life = {
        gid = 2200;
      };

      # Rule 11 (Podman subnets → internet, outbound NAT); the nft header comment is in home-automation/server.
      networking.firewall.extraForwardRules = ''
        ip saddr ${config.vars.network.podmanSubnets.life} accept comment "life pods outbound"
      '';
    };
}
