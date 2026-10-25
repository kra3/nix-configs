{
  flake.nixosModules.services-media-players-navidrome =
    { pkgs, inputs, ... }:
    {
      users.groups.media = {
        gid = 2000;
      };

      services.navidrome = {
        enable = true;
        openFirewall = false;
        # 26.05 module points Plugins.Folder at ${finalPackage}/share/plugins, which the unstable wrapper only creates when a plugin is bundled.
        package =
          inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.navidrome.override
            {
              wasmPlugins = [ (pkgs.runCommand "navidrome-plugins-dir" { } "mkdir -p $out/share/plugins") ];
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
