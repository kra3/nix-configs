{
  flake.nixosModules.profiles-edge =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.services-proxy-nginx
        flakeModules.nixos.services-infrastructure-authelia
        flakeModules.nixos.services-infrastructure-homepage
        flakeModules.nixos.services-tailscale
        flakeModules.nixos.users-authelia
      ];
    };
}
