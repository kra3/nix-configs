{
  # Not de-duplicated across profiles: import once from the host, not from each media profile.
  flake.nixosModules.profiles-media-shared =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.containers-media-mgmt-network
        flakeModules.nixos.containers-media-mgmt-storage
        flakeModules.nixos.containers-media-mgmt-prowlarr
        flakeModules.nixos.containers-media-mgmt-sabnzbd
      ];
    };
}
