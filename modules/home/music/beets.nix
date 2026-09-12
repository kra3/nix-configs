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
        # beets-minimal (not a `dependencies` entry) satisfies the runtime-deps-check hook's
        # `beets>=1.6.0` requirement without propagating a second `beets` into the closure of
        # the overridden beets this plugin gets installed into (nixpkgs' own beets-alternatives
        # package uses this exact same pattern for the same reason).
        nativeBuildInputs = [ pkgs.python3.pkgs.beets-minimal ];
        dependencies = [
          pkgs.python3.pkgs.requests
          pkgs.python3.pkgs.pillow
          musicapy
        ];
        # _get_track() already fetches JioSaavn's 'music' (composer) field as an artist
        # fallback but never surfaces it as beets' own composer field — add that here.
        postPatch = ''
          substituteInPlace beetsplug/jiosaavn.py \
            --replace-fail \
              "jiosaavn_updated=time.time()," \
              "jiosaavn_updated=time.time(),
            composer=track_data.get('music'),"
        '';
        doCheck = false;
      };
    in
    {
      programs.beets = {
        enable = true;
        # pkgs.beets is just `toPythonApplication python3.pkgs.beets`; pluginOverrides only
        # exists on the underlying python3.pkgs.beets derivation, so override there and rewrap.
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
          directory = "/srv/media/library/music/Western";
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

      # acoustid.apikey and spotify.client_id/client_secret live outside this tracked config,
      # in the sops-rendered overlay this alias points `beet` at (see modules/users/kra3.nix's
      # "music/beets-secrets.yaml" template).
      home.shellAliases.beet = "beet --config /run/secrets/rendered/music/beets-secrets.yaml";

      # Second beets profile for Indian film soundtracks: invoked explicitly via
      # `beet -c ~/.config/beets/indian-film.yaml <command>`, not through programs.beets.
      home.file.".config/beets/indian-film.yaml".text = ''
        directory: /srv/media/library/music
        library: ${config.home.homeDirectory}/.config/beets/indian-film.db
        plugins: spotify jiosaavn fetchart embedart zero duplicates fromfilename edit
        zero:
          fields: comments
        embedart:
          maxwidth: 1000
        import:
          move: yes
          write: yes
        paths:
          default: "%the{$albumartist}/$album ($year)/$track - $title"
      '';
    };
}
