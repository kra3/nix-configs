{ ... }:
{
  imports = [
    ./network.nix
    ./storage.nix
    # services
    ./radarr.nix
    ./sonarr.nix
    ./prowlarr.nix
    ./sabnzbd.nix
    ./bazarr.nix
    ./lidarr.nix
    ./seerr.nix
    ./recyclarr.nix
  ];
}
