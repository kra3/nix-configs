{
  flake.nixosModules.profiles-base-server =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.vars
        flakeModules.nixos.services-system-nix-defaults-nixos
        flakeModules.nixos.services-infrastructure-openssh
        flakeModules.nixos.services-infrastructure-sops
        flakeModules.nixos.services-infrastructure-acme
        flakeModules.nixos.fail2ban
        flakeModules.nixos.profiles-observability-agent
      ];
    };
}
