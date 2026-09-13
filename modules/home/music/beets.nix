{
  flake.homeManagerModules.home-music-beets =
    { pkgs, config, ... }:
    let
      # beets-jiosaavn's actual runtime import (musicapy.saavn_api.api) isn't in nixpkgs.
      musicapy = pkgs.python3.pkgs.buildPythonPackage {
        pname = "musicapy";
        version = "2.2.1";
        pyproject = true;
        src = pkgs.fetchFromGitHub {
          owner = "dmdhrumilmistry";
          repo = "MusicAPy";
          rev = "a7a0fe61e65c8d18c0f2cfe86ca3458aa6ec5a4a";
          hash = "sha256-OXQflVKs7VHEkN+oFyOZQXPx2Fz8Es662dV/l62d/BE=";
        };
        build-system = [ pkgs.python3.pkgs.poetry-core ];
        dependencies = [
          pkgs.python3.pkgs.requests
          pkgs.python3.pkgs.wget
        ];
        doCheck = false;
      };

      beets-jiosaavn = pkgs.python3.pkgs.buildPythonPackage {
        pname = "beets-jiosaavn";
        version = "unstable-2026-03-14";
        pyproject = true;
        src = pkgs.fetchFromGitHub {
          owner = "arsaboo";
          repo = "beets-jiosaavn";
          rev = "c965b53e81179b0d11ed97019ac2d597697e02e8";
          hash = "sha256-Vnwl596L+lx0DEM1iDUHys65b6jFtQvBgq3bkjwmlZM=";
        };
        build-system = [ pkgs.python3.pkgs.setuptools ];
        # beets-minimal satisfies the runtime beets>=1.6.0 check without a second beets in the closure.
        nativeBuildInputs = [ pkgs.python3.pkgs.beets-minimal ];
        dependencies = [
          pkgs.python3.pkgs.requests
          pkgs.python3.pkgs.pillow
          musicapy
        ];
        # Surfaces JioSaavn's 'music'/'language' fields as beets' own composer/language.
        postPatch = ''
          substituteInPlace beetsplug/jiosaavn.py \
            --replace-fail \
              "jiosaavn_updated=time.time()," \
              "jiosaavn_updated=time.time(),
            composer=track_data.get('music'),
            language=track_data.get('language') or track_data.get('more_info', {}).get('language'),"
        '';
        doCheck = false;
      };
    in
    {
      programs.beets = {
        enable = true;
        # pluginOverrides only exists on python3.pkgs.beets, so override there and rewrap.
        package = pkgs.python3.pkgs.toPythonApplication (
          pkgs.python3.pkgs.beets.override {
            pluginOverrides = {
              jiosaavn = {
                enable = true;
                propagatedBuildInputs = [ beets-jiosaavn ];
              };
            };
          }
        );
        settings = {
          # music.new is the staged tree Task 11's cutover renames to music/.
          directory = "/srv/media/library/music.new/Western";
          library = "${config.home.homeDirectory}/.config/beets/western.db";
          plugins = [
            "chroma"
            "spotify"
            "fetchart"
            "embedart"
            "lastgenre"
            "zero"
            "duplicates"
            "fromfilename"
            "edit"
          ];
          lastgenre = {
            source = "track";
            count = 1;
          };
          zero = {
            fields = [
              "comments"
            ];
          };
          embedart.maxwidth = 1000;
          import = {
            move = true;
            write = true;
          };
          paths = {
            default = "$albumartist/$album ($year)/$track - $title";
            comp = "$albumartist/$album ($year)/$track - $title";
          };
        };
      };

      # acoustid/spotify credentials live in the sops-rendered overlay this points at.
      home.shellAliases.beet = "beet --config /run/secrets/rendered/music/beets-secrets.yaml";

      # BEETSDIR keeps this profile separate from Western's paths.comp etc.
      home.shellAliases.beet-indian-film = "BEETSDIR=${config.home.homeDirectory}/.config/beets-indian-film beet --config /run/secrets/rendered/music/beets-secrets.yaml";

      home.file.".config/beets-indian-film/config.yaml".text = ''
        # music.new is the staged tree Task 11's cutover renames to music/; beets only
        # auto-relocates items inside their own configured directory.
        directory: /srv/media/library/music.new
        library: ${config.home.homeDirectory}/.config/beets/indian-film.db
        plugins: spotify jiosaavn fetchart embedart lastgenre zero duplicates fromfilename edit
        lastgenre:
          source: track
          count: 1
        zero:
          fields: comments
        embedart:
          maxwidth: 1000
        import:
          move: yes
          write: yes
        paths:
          default: "$albumartist/$album ($year)/$track - $title"
          singleton: "$albumartist/$album ($year)/$track - $title"
      '';
    };
}
