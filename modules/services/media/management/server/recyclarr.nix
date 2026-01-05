{
  services.recyclarr = {
    enable = true;
    schedule = "daily";
    command = "sync";
    configuration = {
      # https://trash-guides.info/Radarr/
      radarr = {
        movie = {
          base_url = "http://10.0.50.4:7878";
          api_key = {
            _secret = "/run/credentials/recyclarr.service/radarr-api_key";
          };
          delete_old_custom_formats = true;
          replace_existing_custom_formats = true;

          media_naming = {
            folder = "jellyfin-tmdb";
            movie = {
              rename = true;
              standard = "jellyfin-tmdb"; 
            };
          };

          include = [
            # Movies
            { template = "radarr-quality-definition-movie"; }
            # UHD Bluray + WEB (4K)
            { template = "radarr-quality-profile-uhd-bluray-web"; }
            { template = "radarr-custom-formats-uhd-bluray-web"; }
            # Remux + WEB 1080p
            # { template = "radarr-quality-profile-remux-web-1080p"; }
            # { template = "radarr-custom-formats-remux-web-1080p"; }

            # Anime
            { template = "radarr-quality-definition-anime"; }
            { template = "radarr-quality-profile-anime"; }
            { template = "radarr-custom-formats-anime"; }
          ];
          custom_formats = [ 
            # Audio
            {
              assign_scores_to = [ { name = "UHD Bluray + WEB"; } ];
              trash_ids = [
                 # 496f355514737f7d83bf7aa4d24f8169 # TrueHD Atmos
                "2f22d89048b01681dde8afe203bf2e95" # DTS X
                "417804f7f2c4308c1f4c5d380d4c4475" # ATMOS (undefined)
                "1af239278386be2919e1bcee0bde047e" # DD+ ATMOS
                "3cafb66171b47f226146a0770576870f" # TrueHD
                 # dcf3ec6938fa32445f590a4da84256cd # DTS-HD MA
                 # a570d4a0e56a2874b64e5bfa55202a1b # FLAC
                 # e7c2fcae07cbada050a0af3357491d7b # PCM
                 # 8e109e50e0a0b83a5098b056e13bf6db # DTS-HD HRA
                "185f1dd7264c4562b9022d963ac37424" # DD+
                 # f9f847ac70a0af62ea4a08280b859636 # DTS-ES
                "1c1a4c5e823891c75bc50380a6866f73" # DTS
                 # 240770601cc226190c367ef59aba7463 # AAC
                 # c2998bd0d90ed5621d8df281e839436e # DD
              ];
            }
            # Movie Versions
            {
              assign_scores_to = [ { name = "UHD Bluray + WEB"; } ];
              trash_ids = [
                # 570bc9ebecd92723d2d21500f4be314c # Remaster
                # eca37840c13c6ef2dd0262b141a5482f # 4K Remaster
                # e0c07d59beb37348e975a930d5e50319 # Criterion Collection
                # 9d27d9d2181838f76dee150882bdc58c # Masters of Cinema
                # db9b4c4b53d312a3ca5f1378f6440fc9 # Vinegar Syndrome
                # 957d0f44b592285f26449575e8b1167e # Special Edition
                # eecf3a857724171f968a66cb5719e152 # IMAX
                # 9f6cbff8cfe4ebbc1bde14c7b7bec0de # IMAX Enhanced
              ];
            }
            # Optional
            {
              assign_scores_to = [ { name = "UHD Bluray + WEB"; } ];
              trash_ids = [
                # b6832f586342ef70d9c128d40c07b872 # Bad Dual Groups
                # cc444569854e9de0b084ab2b8b1532b2 # Black and White Editions
                # ae9b7c9ebde1f3bd336a8cbd1ec4c5e5 # No-RlsGroup
                # 7357cf5161efbf8c4d5d0c30b4815ee2 # Obfuscated
                # 5c44f52a8714fdd79bb4d98e2673be1f # Retags
                # f537cf427b64c38c8e36298f657e4828 # Scene
              ];
            }
            {
              assign_scores_to = [ { name = "UHD Bluray + WEB"; } ];
              trash_ids = [
                # Comment out the next line if you and all of your users' setups are fully DV compatible
                # "923b6abef9b17f937fab56cfcf89e1f1" # DV (w/o HDR fallback)

                # HDR10+ Boost - Uncomment the HDR10+ Boost line if you want to prefer HDR10+ releases
                # DV Boost - Uncomment the DV Boost line if you want to prefer DV releases
                # Uncomment both lines if you want to prefer both (DV HDR10+)
                # b337d6812e06c200ec9a2d3cfa9d20a7 # DV Boost
                # caa37d0df9c348912df1fb1d88f9273a # HDR10+ Boost
              ];
            }
            # Optional SDR
            # Only ever use ONE of the following custom formats:
            # SDR - block ALL SDR releases
            # SDR (no WEBDL) - block UHD/4k Remux and Bluray encode SDR releases, but allow SDR WEB
            {
              assign_scores_to = [ { name = "UHD Bluray + WEB"; } ];
              trash_ids = [
                "9c38ebb7384dada637be8899efa68e6f" # SDR
                # 25c12f78430a3a23413652cbd1d48d77 # SDR (no WEBDL)
              ];
            }

            # Anime
            {
              assign_scores_to = [ { name = "Remux-1080p - Anime"; score = 1; } ];
              trash_ids = [
                "064af5f084a0a24458cc8ecd3220f93f" # Uncensored
              ];
            }
            {
              assign_scores_to = [ { name = "Remux-1080p - Anime"; score = 0; } ];
              trash_ids = [
                "a5d148168c4506b55cf53984107c396e" # 10bit
              ];
            }
            {
              assign_scores_to = [ { name = "Remux-1080p - Anime"; score = 0; } ];
              trash_ids = [
                "4a3b087eea2ce012fcc1ce319259a3be" # Anime Dual Audio
              ];
            }
          ];
        };
      };

      # https://trash-guides.info/Sonarr/
      sonarr = {
        tv = {
          base_url = "http://10.0.50.4:8989";
          api_key = {
            _secret = "/run/credentials/recyclarr.service/sonarr-api_key";
          };
          delete_old_custom_formats = true;
          replace_existing_custom_formats = true;

          media_naming = {
            season = "default";
            series = "jellyfin-tvdb";
            episodes = {
              rename = true;
              standard = "default";
              daily = "default";
              anime = "default";
            };
          };

          include = [
            { template = "sonarr-quality-definition-series"; }
            # pick one of next 2
            { template = "sonarr-v4-quality-profile-web-1080p"; }
            # { template = "sonarr-v4-quality-profile-web-1080p-alternative"; }
            { template = "sonarr-v4-custom-formats-web-1080p"; }

            # Anime
            { template = "sonarr-quality-definition-anime"; }
            { template = "sonarr-v4-quality-profile-anime"; }
            { template = "sonarr-v4-custom-formats-anime"; } 
          ];
          custom_formats = [
            {
              assign_scores_to = [ { name = "WEB-1080p"; } ];
              trash_ids = [
                  "32b367365729d530ca1c124a0b180c64" # Bad Dual Groups
                  # 82d40da2bc6923f41e14394075dd4b03 # No-RlsGroup
                  # e1a997ddb54e3ecbfe06341ad323c458 # Obfuscated
                  # 06d66ab109d4d2eddb2794d21526d140 # Retags
                  # 1b3994c551cbb92a2c781af061f4ab44 # Scene
              ];
            }
            # Anime
            {
              assign_scores_to = [ { name = "Remux-1080p - Anime"; score = 1; } ];
              trash_ids = [
                "026d5aadd1a6b4e550b134cb6c72b3ca" # Uncensored
              ];
            }
            {
              assign_scores_to = [ { name = "Remux-1080p - Anime"; score = 0; } ];
              trash_ids = [
                "b2550eb333d27b75833e25b8c2557b38" # 10bit
              ];
            }
            {
              assign_scores_to = [ { name = "Remux-1080p - Anime"; score = 0; } ];
              trash_ids = [
                "418f50b10f1907201b6cfdf881f467b7" # Anime Dual Audio
              ];
            }
          ];
        };
      };
    };
  };

  systemd.services.recyclarr = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig.LoadCredential = [
      "radarr-api_key:/run/secrets/media.recyclarr.radarr_api_key"
      "sonarr-api_key:/run/secrets/media.recyclarr.sonarr_api_key"
    ];
  };
}
