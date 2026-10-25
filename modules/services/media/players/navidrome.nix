{
  flake.nixosModules.services-media-players-navidrome =
    { pkgs, inputs, ... }:
    let
      unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
      prebuiltPlugin =
        name: url: hash:
        pkgs.runCommand "navidrome-plugin-${name}" { } ''
          install -Dm444 ${pkgs.fetchurl { inherit url hash; }} $out/share/plugins/${name}.ndp
        '';
    in
    {
      users.groups.media = {
        gid = 2000;
      };

      services.navidrome = {
        enable = true;
        openFirewall = false;
        # Keep at least one plugin: the 26.05 module's Plugins.Folder only exists when the unstable wrapper bundles one.
        package = unstable.navidrome.override {
          wasmPlugins = with unstable.pkgsCross.wasi32.navidromePlugins; [
            apple-music
            listenbrainz-daily-playlist
            lyrics-plugin
            (prebuiltPlugin "genre-mixes"
              "https://github.com/Aut0iq/navidrome-genre-mixes/releases/download/v0.3.0/genre-mixes.ndp"
              "sha256-xpJI0M9gumBfI38ljRme4J51wFTLgvIAU+84g92fwa8="
            )
            (prebuiltPlugin "navibeat-mixes"
              "https://github.com/nenadjokic/navibeat-mixes/releases/download/v0.9.25/navibeat-mixes-navidrome-0.64.ndp"
              "sha256-pk4oNBT3guDYpfxAQ5QGFuUlnn8LWO/HSrH4lzhlXrw="
            )
            (prebuiltPlugin "play-it-again"
              "https://github.com/bcorporaal/navidrome-play-it-again/releases/download/v2.0.0/play-it-again.ndp"
              "sha256-IIZ1f1ex1Tu3syu7zDKzBq8KVR14N/lKvxghgXTvM/s="
            )
          ];
        };
        settings = {
          Address = "0.0.0.0";
          Port = 4533;
          MusicFolder = "/data/library/music";
          PlaylistsPath = "playlists";
          DataFolder = "/var/lib/navidrome/data";
          "Prometheus.Enabled" = true;
        };
      };

      users.users.navidrome = {
        extraGroups = [ "media" ];
      };

      systemd.services.navidrome = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
      };

    };
}
