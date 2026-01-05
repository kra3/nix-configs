{
  imports = [
    # Movies
    ./radarr.nix
    # TV
    ./sonarr.nix
    # Music
    ./lidarr.nix
    # Subtitles
    ./bazarr.nix
    # Profile sync
    ./recyclarr.nix
    # Indexer sync
    ./prowlarr.nix
    # usenet downloader
    ./sabnzbd.nix
    # media management
    ./jellyseerr.nix
  ];
}
