{
  # The key makes the module system drop repeat imports, so every media profile can import this.
  flake.nixosModules.profiles-media-shared =
    { config, flakeModules, ... }:
    {
      key = "profiles-media-shared";
      imports = [
        flakeModules.nixos.containers-media-mgmt-network
        flakeModules.nixos.containers-media-mgmt-storage
        flakeModules.nixos.containers-media-mgmt-prowlarr
        flakeModules.nixos.containers-media-mgmt-sabnzbd
      ];

      # Rule 11 (Podman subnets → internet, outbound NAT); the nft header comment is in home-automation/server.
      networking.firewall.extraForwardRules = ''
        ip saddr ${config.vars.network.podmanSubnets.mediaMgmt} accept comment "media-mgmt pods outbound"
      '';
    };
}
