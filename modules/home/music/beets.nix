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

      beets-aisauce = pkgs.python3.pkgs.buildPythonPackage {
        pname = "beets-aisauce";
        version = "0.2.1";
        pyproject = true;
        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/0c/eb/6cf25702a430bc7227091689990f18be290cff4b7f142df6af8eb1782d03/beets_aisauce-0.2.1.tar.gz";
          hash = "sha256-K+TmweC5qBxogDFMC9ekC0z6A97Cqj9OKYjB1eH6RKA=";
        };
        build-system = [ pkgs.python3.pkgs.setuptools ];
        nativeBuildInputs = [ pkgs.python3.pkgs.beets-minimal ];
        dependencies = [
          pkgs.python3.pkgs.openai
          pkgs.python3.pkgs.instructor
        ];
        # instructor's default tool-calling mode forces tool_choice, which current Deepseek
        # models reject while their "thinking" mode is on (the plugin has no config knob for
        # that). JSON mode gets structured output without tool_choice, sidestepping it.
        #
        # beets 2.13.1 renamed Item's `genre` field to `genres`; the plugin still writes
        # `item.genre`, crashing metadata_cleanup's apply_to_items on every candidate.
        postPatch = ''
          sed -i '/base_url=provider\["api_base_url"\],/{n;s/^        )$/        ),\n        mode=instructor.Mode.JSON,/}' beetsplug/aisauce/ai.py
          sed -i 's/item\.genre\b/item.genres/g' beetsplug/aisauce/types.py
        '';
        doCheck = false;
      };

      # Local plugin: normalizes artist/albumartist initials ("S.P." -> "SP") and unifies
      # the multi-credit separator to ", " on every future import/write, matching the
      # library-wide cleanup pass done manually on the existing Indian-film buckets.
      beets-normalize-names = pkgs.python3.pkgs.buildPythonPackage {
        pname = "beets-normalize-names";
        version = "0.1.0";
        pyproject = true;
        src = ./beets-plugins;
        build-system = [ pkgs.python3.pkgs.setuptools ];
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
              aisauce = {
                enable = true;
                propagatedBuildInputs = [ beets-aisauce ];
              };
              normalize_names = {
                enable = true;
                propagatedBuildInputs = [ beets-normalize-names ];
              };
            };
          }
        );
        settings = {
          directory = "/srv/media/library/music/Western";
          library = "${config.home.homeDirectory}/.config/beets/western.db";
          plugins = [
            "musicbrainz"
            "chroma"
            "spotify"
            "fetchart"
            "embedart"
            "lastgenre"
            "zero"
            "duplicates"
            "fromfilename"
            "edit"
            "normalize_names"
          ];
          # aisauce is opt-in (see beet-cleanup/beet-indian-film-cleanup), not run on every
          # regular import -- it's an LLM-backed helper, not needed for routine matches.
          # Lidarr shares this host's IP and also queries MusicBrainz; stay under the combined rate limit.
          musicbrainz.ratelimit_interval = 1.5;
          # Max out Spotify's match-distance penalty (valid range is 0.0-1.0) so MusicBrainz wins ties for mb_trackid.
          spotify.data_source_mismatch_penalty = 1.0;
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
          # fanarttv_key (secret) lives in the beets-secrets.yaml overlay; this just
          # opts the source into the default list, which omits it otherwise.
          fetchart.sources = [
            "filesystem"
            "coverart"
            "itunes"
            "amazon"
            "albumart"
            "cover_art_url"
            "fanarttv"
          ];
          import = {
            move = true;
            write = true;
          };
          paths = {
            default = "$albumartist/$album ($year)/$track - $title";
            comp = "$albumartist/$album ($year)/$track - $title";
            singleton = "$albumartist/$album ($year)/$track - $title";
          };
        };
      };

      # acoustid/spotify credentials live in the sops-rendered overlay this points at.
      home.shellAliases.beet = "beet --config /run/secrets/rendered/music/beets-secrets.yaml";

      # BEETSDIR keeps this profile separate from Western's paths.comp etc.
      home.shellAliases.beet-indian-film = "BEETSDIR=${config.home.homeDirectory}/.config/beets-indian-film beet --config /run/secrets/rendered/music/beets-secrets.yaml";

      # aisauce.mode is single-valued (metadata_source XOR metadata_cleanup); these use a
      # separate sops template (beets-cleanup-secrets.yaml) rather than a small overlay
      # file, since beets' --config doesn't stack (last one wins) and a partial overlay
      # would silently drop the providers list set by the metadata_source template.
      home.shellAliases.beet-cleanup = "beet --config /run/secrets/rendered/music/beets-cleanup-secrets.yaml";
      home.shellAliases.beet-indian-film-cleanup = "BEETSDIR=${config.home.homeDirectory}/.config/beets-indian-film beet --config /run/secrets/rendered/music/beets-cleanup-secrets.yaml";

      home.file.".config/beets-indian-film/config.yaml".text = ''
        directory: /srv/media/library/music
        library: ${config.home.homeDirectory}/.config/beets/indian-film.db
        # aisauce is opt-in (see beet-indian-film-cleanup), not run on every regular import.
        plugins: musicbrainz chroma spotify jiosaavn fetchart embedart lastgenre zero duplicates fromfilename edit normalize_names
        # Lidarr shares this host's IP and also queries MusicBrainz; stay under the combined rate limit.
        musicbrainz:
          ratelimit_interval: 1.5
        lastgenre:
          source: track
          count: 1
        zero:
          fields: comments
        embedart:
          maxwidth: 1000
        fetchart:
          sources:
            - filesystem
            - coverart
            - itunes
            - amazon
            - albumart
            - cover_art_url
            - fanarttv
        import:
          move: yes
          write: yes
        paths:
          default: "$albumartist/$album ($year)/$track - $title"
          singleton: "$albumartist/$album ($year)/$track - $title"
          comp: "$albumartist/$album ($year)/$track - $title"
        # VA-flagged soundtracks add distance penalty; default 0.04 demotes correct matches to skip.
        match:
          strong_rec_thresh: 0.15
      '';
    };
}
