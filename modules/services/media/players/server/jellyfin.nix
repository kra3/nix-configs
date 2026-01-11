{ pkgs, ... }:
{
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
  environment.sessionVariables.LIBVA_DRIVERS_PATH = "${pkgs.intel-media-driver}/lib/dri";
  environment.systemPackages = with pkgs; [
    intel-media-driver
    intel-vaapi-driver
    libva-utils
  ];

  users.groups.media = {
    gid = 2000;
  };

  services.declarative-jellyfin = {
    enable = true;
    openFirewall = true;

    system = {
      serverName = "sutala";
      trickplayOptions = {
        enableHwAcceleration = true;
        enableHwEncoding = true;
      };
      pluginRepositories = [
        {
          tag = "RepositoryInfo";
          content = {
            Name = "Jellyfin Stable";
            Url = "https://repo.jellyfin.org/files/plugin/manifest.json";
          };
        }
        {
          tag = "RepositoryInfo";
          content = {
            Name = "SSO";
            Url = "https://raw.githubusercontent.com/9p4/jellyfin-plugin-sso/manifest-release/manifest.json";
          };
        }
        {
          tag = "RepositoryInfo";
          content = {
            Name = "Intro Skipper";
            Url = "https://intro-skipper.org/manifest.json";
          };
        }
        {
          tag = "RepositoryInfo";
          content = {
            Name = "Paradox Plugins";
            Url = "https://www.iamparadox.dev/jellyfin/plugins/manifest.json";
          };
        }
        {
          tag = "RepositoryInfo";
          content = {
            Name = "Jellyfin Tweaks + Enhanced";
            Url = "https://raw.githubusercontent.com/n00bcodr/jellyfin-plugins/main/10.11/manifest.json";
          };
        }
        {
          tag = "RepositoryInfo";
          content = {
            Name = "Streamyfin";
            Url = "https://raw.githubusercontent.com/streamyfin/jellyfin-plugin-streamyfin/main/manifest.json";
          };
        }
      ];
    };

    network = {
      enableIPv6 = false;
      enableHttps = false;
      internalHttpPort = 8096;
      publicHttpPort = 8096;
      publishedServerUriBySubnet = [
        "all=https://jellyfin.karunagath.in"
      ];
    };

    encoding = {
      enableHardwareEncoding = true;
      hardwareAccelerationType = "qsv";
      qsvDevice = "/dev/dri/renderD128";
      vaapiDevice = "/dev/dri/renderD128";
      enableDecodingColorDepth10Hevc = true;
      enableIntelLowPowerH264HwEncoder = true;
      enableIntelLowPowerHevcHwEncoder = true;
      enableTonemapping = true;
      enableVppTonemapping = true;
      tonemappingAlgorithm = "bt2390";
      allowHevcEncoding = true;
      allowAv1Encoding = true;
      hardwareDecodingCodecs = [
        "h264"
        "hevc"
        "mpeg2video"
        "vc1"
        "vp9"
        "vp8"
        "av1"
      ];
    };

    libraries = {
      Movies = {
        contentType = "movies";
        pathInfos = [ "/data/library/movies" ];
      };
      TV = {
        contentType = "tvshows";
        pathInfos = [ "/data/library/tv" ];
      };
      "Anime Movies" = {
        contentType = "movies";
        pathInfos = [ "/data/library/anime/movies" ];
      };
      "Anime TV" = {
        contentType = "tvshows";
        pathInfos = [ "/data/library/anime/tv" ];
      };
      "Home Videos" = {
        contentType = "homevideos";
        pathInfos = [ "/data/library/homevideos" ];
      };
    };

    users = {
      kra3 = {
        mutable = false;
        hashedPasswordFile = "/run/secrets/media.jellyfin.users.kra3.password";
        permissions.isAdministrator = true;
        permissions.isDisabled = false;
      };
      home = {
        mutable = false;
        enableAutoLogin = true;
        hashedPasswordFile = "/run/secrets/media.jellyfin.users.home.password";
      };
    };

    apikeys = {
      Jellyseerr = {
        keyPath = "/run/secrets/media.jellyfin.apikeys.jellyseerr";
      };
    };

    branding = {
      customCss = ''
        /* using https://github.com/ranaldsgift/KefinTweaks instead gives much more options */
        /* @import url("https://cdn.jsdelivr.net/gh/lscambo13/ElegantFin@main/Theme/ElegantFin-jellyfin-theme-build-latest-minified.css"); */
        /* @import url('https://cdn.jsdelivr.net/gh/stpnwf/ZestyTheme@latest/theme.css'); */
        /* cyan is default, others: blue, coral, grey, green, purple, red, yellow */
        /* @import url('https://cdn.jsdelivr.net/gh/stpnwf/ZestyTheme@latest/colorschemes/blue.css'); */
      '';
    };
  };

  users.users.jellyfin = {
    extraGroups = [
      "media"
      "render"
      "video"
    ];
  };

  systemd.services.jellyfin = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}
