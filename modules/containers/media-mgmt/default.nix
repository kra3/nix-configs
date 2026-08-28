{
  flake.nixosModules.containers-media-mgmt-default = { flakeModules, ... }: {
    imports = [
      flakeModules.nixos.containers-media-mgmt-network
      flakeModules.nixos.containers-media-mgmt-storage
      # services
      flakeModules.nixos.containers-media-mgmt-radarr
      flakeModules.nixos.containers-media-mgmt-sonarr
      flakeModules.nixos.containers-media-mgmt-prowlarr
      flakeModules.nixos.containers-media-mgmt-sabnzbd
      flakeModules.nixos.containers-media-mgmt-bazarr
      flakeModules.nixos.containers-media-mgmt-lidarr
      flakeModules.nixos.containers-media-mgmt-bookshelf
      flakeModules.nixos.containers-media-mgmt-audiobookshelf
      flakeModules.nixos.containers-media-mgmt-seerr
      flakeModules.nixos.containers-media-mgmt-recyclarr
      flakeModules.nixos.containers-media-mgmt-unpackerr
      flakeModules.nixos.containers-media-mgmt-maintainerr
    ];
  };
}
