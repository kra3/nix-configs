{
  # The key makes the module system drop repeat imports, so every media profile can import this.
  flake.nixosModules.profiles-media-shared =
    { flakeModules, ... }:
    {
      key = "profiles-media-shared";
      imports = [
        flakeModules.nixos.containers-media-mgmt-network
        flakeModules.nixos.containers-media-mgmt-storage
        flakeModules.nixos.containers-media-mgmt-prowlarr
        flakeModules.nixos.containers-media-mgmt-sabnzbd
      ];
    };
}
