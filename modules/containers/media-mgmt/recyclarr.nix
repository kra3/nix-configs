{
  flake.nixosModules.containers-media-mgmt-recyclarr =
    {
      config,
      pkgs,
      flakeLib,
      flakeModules,
      ...
    }:
    let
      network = config.virtualisation.quadlet.networks.media-mgmt;
      ip = config.vars.network.podmanAddresses.recyclarr;

      recyclarrConfig = pkgs.writeText "recyclarr.yml" ''
        radarr:
          movie:
            base_url: http://radarr:7878
            api_key: !secret radarr_api_key
            delete_old_custom_formats: true

            media_naming:
              folder: jellyfin-tmdb
              movie:
                rename: true
                standard: jellyfin-tmdb

            quality_definition:
              type: movie

            quality_profiles:
              - trash_id: 64fb5f9858489bdac2af690e27c8f42f # UHD Bluray + WEB
                name: UHD Bluray + WEB
                upgrade:
                  allowed: true
                  until_quality: Bluray-2160p
                qualities:
                  - name: Bluray-2160p
                  - name: WEB 2160p
                    qualities:
                      - WEBDL-2160p
                      - WEBRip-2160p
                  - name: Bluray-1080p
                  - name: WEB 1080p
                    qualities:
                      - WEBDL-1080p
                      - WEBRip-1080p
                reset_unmatched_scores:
                  enabled: true

              - trash_id: 722b624f9af1e492284c4bc842153a38 # [Anime] Remux-1080p
                name: Remux-1080p - Anime
                reset_unmatched_scores:
                  enabled: true

            custom_format_groups:
              skip:
                - 9d5acd8f1da78dfbae788182f7605200 # [Audio] Audio Formats
              add:
                - trash_id: ff204bbcecdd487d1cefcefdbf0c278d # [Optional] Golden Rule UHD
                - trash_id: a3ac6af01d78e4f21fcb75f601ac96df # [Unwanted] Unwanted Formats
                  exclude:
                    - b6832f586342ef70d9c128d40c07b872 # Bad Dual Groups
                    - cc444569854e9de0b084ab2b8b1532b2 # Black and White Editions

            custom_formats:
              # Audio
              - assign_scores_to:
                  - name: UHD Bluray + WEB
                trash_ids:
                  # - 496f355514737f7d83bf7aa4d24f8169 # TrueHD Atmos
                  - 2f22d89048b01681dde8afe203bf2e95 # DTS X
                  - 417804f7f2c4308c1f4c5d380d4c4475 # ATMOS (undefined)
                  - 1af239278386be2919e1bcee0bde047e # DD+ ATMOS
                  - 3cafb66171b47f226146a0770576870f # TrueHD
                  # - dcf3ec6938fa32445f590a4da84256cd # DTS-HD MA
                  # - a570d4a0e56a2874b64e5bfa55202a1b # FLAC
                  # - e7c2fcae07cbada050a0af3357491d7b # PCM
                  # - 8e109e50e0a0b83a5098b056e13bf6db # DTS-HD HRA
                  - 185f1dd7264c4562b9022d963ac37424 # DD+
                  # - f9f847ac70a0af62ea4a08280b859636 # DTS-ES
                  - 1c1a4c5e823891c75bc50380a6866f73 # DTS
                  # - 240770601cc226190c367ef59aba7463 # AAC
                  # - c2998bd0d90ed5621d8df281e839436e # DD

              # Movie Versions (all commented out — uncomment to enable)
              # - assign_scores_to:
              #     - name: UHD Bluray + WEB
              #   trash_ids:
              #     - 570bc9ebecd92723d2d21500f4be314c # Remaster
              #     - eca37840c13c6ef2dd0262b141a5482f # 4K Remaster
              #     - e0c07d59beb37348e975a930d5e50319 # Criterion Collection
              #     - 9d27d9d2181838f76dee150882bdc58c # Masters of Cinema
              #     - db9b4c4b53d312a3ca5f1378f6440fc9 # Vinegar Syndrome
              #     - 957d0f44b592285f26449575e8b1167e # Special Edition
              #     - eecf3a857724171f968a66cb5719e152 # IMAX
              #     - 9f6cbff8cfe4ebbc1bde14c7b7bec0de # IMAX Enhanced

              # Optional (all commented out — uncomment to enable)
              # - assign_scores_to:
              #     - name: UHD Bluray + WEB
              #   trash_ids:
              #     - b6832f586342ef70d9c128d40c07b872 # Bad Dual Groups
              #     - cc444569854e9de0b084ab2b8b1532b2 # Black and White Editions
              #     - ae9b7c9ebde1f3bd336a8cbd1ec4c5e5 # No-RlsGroup
              #     - 7357cf5161efbf8c4d5d0c30b4815ee2 # Obfuscated
              #     - 5c44f52a8714fdd79bb4d98e2673be1f # Retags
              #     - f537cf427b64c38c8e36298f657e4828 # Scene

              # DV / HDR10+ Boost (all commented out — uncomment to enable)
              # - assign_scores_to:
              #     - name: UHD Bluray + WEB
              #   trash_ids:
              #     # Comment out the next line if you and all of your users' setups are fully DV compatible
              #     - 923b6abef9b17f937fab56cfcf89e1f1 # DV (w/o HDR fallback)
              #     - b337d6812e06c200ec9a2d3cfa9d20a7 # DV Boost
              #     - caa37d0df9c348912df1fb1d88f9273a # HDR10+ Boost

              # Optional SDR
              # Only ever use ONE of the following custom formats:
              # SDR - block ALL SDR releases
              # SDR (no WEBDL) - block UHD/4k Remux and Bluray encode SDR releases, but allow SDR WEB
              - assign_scores_to:
                  - name: UHD Bluray + WEB
                trash_ids:
                  - 9c38ebb7384dada637be8899efa68e6f # SDR
                  # - 25c12f78430a3a23413652cbd1d48d77 # SDR (no WEBDL)

              # Anime
              - assign_scores_to:
                  - name: Remux-1080p - Anime
                    score: 1
                trash_ids:
                  - 064af5f084a0a24458cc8ecd3220f93f # Uncensored
              - assign_scores_to:
                  - name: Remux-1080p - Anime
                    score: 0
                trash_ids:
                  - a5d148168c4506b55cf53984107c396e # 10bit
              - assign_scores_to:
                  - name: Remux-1080p - Anime
                    score: 0
                trash_ids:
                  - 4a3b087eea2ce012fcc1ce319259a3be # Anime Dual Audio

        sonarr:
          tv:
            base_url: http://sonarr:8989
            api_key: !secret sonarr_api_key
            delete_old_custom_formats: true

            media_naming:
              season: default
              series: jellyfin-tvdb
              episodes:
                rename: true
                standard: default
                daily: default
                anime: default

            quality_definition:
              type: series

            quality_profiles:
              - trash_id: 72dae194fc92bf828f32cde7744e51a1 # WEB-1080p
                name: WEB-1080p
                reset_unmatched_scores:
                  enabled: true
              - trash_id: 20e0fc959f1f1704bed501f23bdae76f # [Anime] Remux-1080p
                name: Remux-1080p - Anime
                reset_unmatched_scores:
                  enabled: true
              - name: Ultra-HD
                upgrade:
                  allowed: true
                  until_quality: WEB 2160p
                qualities:
                  - name: Bluray-2160p
                  - name: WEB 2160p
                    qualities:
                      - WEBDL-2160p
                      - WEBRip-2160p
                  - name: HDTV-2160p
                  - name: WEB 1080p
                    qualities:
                      - WEBDL-1080p
                      - WEBRip-1080p

            custom_format_groups:
              skip:
                - 74aff4168620ed49dcc67e92b2c2a5b4 # [Optional] Language Profiles
              add:
                - trash_id: 158188097a58d7687dee647e04af0da3 # [Optional] Golden Rule HD
                - trash_id: 85fae4a2294965b75710ef2989c850eb # [Streaming Services] HD/UHD boost
                - trash_id: 59c3af66780d08332fdc64e68297098f # [Unwanted] Unwanted Formats

            custom_formats:
              - assign_scores_to:
                  - name: WEB-1080p
                trash_ids:
                  - 32b367365729d530ca1c124a0b180c64 # Bad Dual Groups
                  # - 82d40da2bc6923f41e14394075dd4b03 # No-RlsGroup
                  # - e1a997ddb54e3ecbfe06341ad323c458 # Obfuscated
                  # - 06d66ab109d4d2eddb2794d21526d140 # Retags
                  # - 1b3994c551cbb92a2c781af061f4ab44 # Scene

              # Anime
              - assign_scores_to:
                  - name: Remux-1080p - Anime
                    score: 1
                trash_ids:
                  - 026d5aadd1a6b4e550b134cb6c72b3ca # Uncensored
              - assign_scores_to:
                  - name: Remux-1080p - Anime
                    score: 0
                trash_ids:
                  - b2550eb333d27b75833e25b8c2557b38 # 10bit
              - assign_scores_to:
                  - name: Remux-1080p - Anime
                    score: 0
                trash_ids:
                  - 418f50b10f1907201b6cfdf881f467b7 # Anime Dual Audio
      '';
    in
    {
      imports = [ flakeModules.nixos.services-media-acquisition-recyclarr ];

      # recyclarr depends on radarr and sonarr api keys, declared in those modules.
      # recyclarr.yml is a static nix-store file (safe — no secrets). secrets.yml is
      # a sops template rendered at runtime with the actual API keys, and stays here
      # since it's this deployment's secrets.
      sops.templates."media.recyclarr.secrets.yml" = {
        owner = "root";
        group = "media";
        mode = "0440";
        content = ''
          radarr_api_key: ${config.sops.placeholder."media.radarr.api_key"}
          sonarr_api_key: ${config.sops.placeholder."media.sonarr.api_key"}
        '';
      };

      virtualisation.quadlet.containers.recyclarr = {
        containerConfig = {
          networks = [ "${network.ref}:ip=${ip}" ];
          volumes = [
            "${recyclarrConfig}:/config/recyclarr.yml:ro"
            "${config.sops.templates."media.recyclarr.secrets.yml".path}:/config/secrets.yml:ro"
            "/srv/appdata/media-mgmt/recyclarr:/config"
          ];
          # Floored above the formula: this window likely caught it idle, not mid-sync.
          memory = "512m";
          podmanArgs = [ "--cpus=1" ];
        };
      }
      // flakeLib.quadlet.mkNetworkDeps {
        networkServices = [ "media-mgmt-network.service" ];
        restart = "on-failure";
      };
    };
}
