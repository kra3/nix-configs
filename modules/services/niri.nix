{ config, pkgs, ... }:
let
  domain = config.vars.acme.domain;

  # Real per-app logos for the selfhosted-menu item picker, from
  # homarr-labs/dashboard-icons (Apache-2.0, https://dashboardicons.com).
  # Pinned to a commit so builds stay reproducible; hashes verify content on fetch.
  dashboardIconsRev = "0f14e7261df700795a98594f3d51e507c123d27c";
  dashboardIcon = name: hash: pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/homarr-labs/dashboard-icons/${dashboardIconsRev}/svg/${name}.svg";
    inherit hash;
  };
  dashboardIcons = {
    jellyfin = dashboardIcon "jellyfin" "sha256-f1PPCD27MRnsjFrL2AScUDMidhfkYVQPcFkawQkSQwY=";
    navidrome = dashboardIcon "navidrome" "sha256-zYkRWBwRc8Bpba2usC+bsusf87a99cZMSbkPfLcCdM8=";
    music-assistant = dashboardIcon "music-assistant" "sha256-Q2A7xPBg88m/RqImohKbMqNZV6/tRgs/7k8IREXUQAM=";
    sonarr = dashboardIcon "sonarr" "sha256-pd6+VlKB6xa3RtdbnOcuIvL7FcGbT1VCj99iuEvnkwY=";
    radarr = dashboardIcon "radarr" "sha256-w9B+zfq0MsqX8mzwH+Btv8CZO1y2CTgns94cdCGm+5U=";
    lidarr = dashboardIcon "lidarr" "sha256-L1X2lFCgygNiHodVDoHsD2eYxKV4tU5LmIqacjSoNkc=";
    bazarr = dashboardIcon "bazarr" "sha256-tCd37mIt34Ws4V2+mnDUcaLKNk50XHPqRn2joKdYYWI=";
    prowlarr = dashboardIcon "prowlarr" "sha256-zXc2vO9lUK2FPlnU1yBflunbiuRL6VfKW36ucEb1vGc=";
    sabnzbd = dashboardIcon "sabnzbd" "sha256-ElP9YuMQ8sfENgAqeGS4E1ZUog02shd+OQBUL8+El7A=";
    seerr = dashboardIcon "seerr" "sha256-sS5d/WQdlhz7aDYNoz/iiHO5Xqm2TCMjPVuHo3y/pMQ=";
    maintainerr = dashboardIcon "maintainerr" "sha256-wTMBLA99rRTGaphWwt+YDMwQQ0XkKHPAdoSGNJveWEE=";
    audiobookshelf = dashboardIcon "audiobookshelf" "sha256-SKU5wme4jjiY+OEn2s7wTmYlpemfjTNMOSqKplZoqOg=";
    home-assistant = dashboardIcon "home-assistant" "sha256-FGs2a4wJUCdCAlxLyk4Cno5KGyd9uDfVmiO5OUDr4OA=";
    zigbee2mqtt = dashboardIcon "zigbee2mqtt" "sha256-VoKVJi5MGrqvCi0p9rDMxSKOxioH6O5qyoh5kEigtFs=";
    frigate = dashboardIcon "frigate" "sha256-LBF2pq9YbnvRSfsxjCJtyGMDO/GI0Hn2qoI8v/zXTJM=";
    actual-budget = dashboardIcon "actual-budget" "sha256-bsZiGo0LafYi/xDX+VeiKflZ2U1LyMXjWGrr5xySJAc=";
    ghostfolio = dashboardIcon "ghostfolio" "sha256-nUgTnvQjLA53nR9mYhS6H7KYr8nGSBSvBee1umoTMXU=";
    grafana = dashboardIcon "grafana" "sha256-jzKJcHPuk1lKsjOUgu8hyjdnBEBV2oniuvkGbSVZLfc=";
    adguard-home = dashboardIcon "adguard-home" "sha256-SmWyOuFr9wDzUTniwQpfcxoyUw8tuDKr1WEr4lI7H58=";
    arcane = dashboardIcon "arcane" "sha256-Gu7bc7t4w5LSFvhdsL13MExO1Ff+KWOYM2p8xsD0JMo=";
  };

  # Two-level fuzzel picker (group, then app) for self-hosted web apps.
  # Native TUI/GUI clients (jftui, ostui, feishin, actual-client) are deliberately
  # left out for now — this round only wires the browser-based apps.
  selfhostedMenu = pkgs.writeShellApplication {
    name = "selfhosted-menu";
    runtimeInputs = [ pkgs.fuzzel pkgs.ungoogled-chromium ];
    text = ''
      domain="${domain}"

      # Group icons come from adwaita-icon-theme-legacy: modern Adwaita dropped
      # these old-style category icons, so this restores just enough of them.
      group_lines() {
        printf 'Media\0icon\x1fmultimedia-player\n'
        printf 'Media Management\0icon\x1ffolder-download\n'
        printf 'Home Automation\0icon\x1fnetwork-workgroup\n'
        printf 'Life\0icon\x1faccessories-calculator\n'
        printf 'Admin\0icon\x1fapplications-system\n'
      }

      # Per-app logos from dashboard-icons; Bookshelf has no icon="" so it
      # falls back to a plain line (no icon annotation for that entry).
      item_line() {
        local name="$1" icon="$2"
        if [ -n "$icon" ]; then
          printf '%s\0icon\x1f%s\n' "$name" "$icon"
        else
          printf '%s\n' "$name"
        fi
      }

      items_for() {
        case "$1" in
          Media)
            item_line Jellyfin "${dashboardIcons.jellyfin}"
            item_line Navidrome "${dashboardIcons.navidrome}"
            item_line "Music Assistant" "${dashboardIcons.music-assistant}"
            ;;
          "Media Management")
            item_line Sonarr "${dashboardIcons.sonarr}"
            item_line Radarr "${dashboardIcons.radarr}"
            item_line Lidarr "${dashboardIcons.lidarr}"
            item_line Bazarr "${dashboardIcons.bazarr}"
            item_line Prowlarr "${dashboardIcons.prowlarr}"
            item_line SABnzbd "${dashboardIcons.sabnzbd}"
            item_line Seerr "${dashboardIcons.seerr}"
            item_line Maintainerr "${dashboardIcons.maintainerr}"
            item_line Audiobookshelf "${dashboardIcons.audiobookshelf}"
            item_line Bookshelf ""
            ;;
          "Home Automation")
            item_line "Home Assistant" "${dashboardIcons.home-assistant}"
            item_line Zigbee2MQTT "${dashboardIcons.zigbee2mqtt}"
            item_line Frigate "${dashboardIcons.frigate}"
            ;;
          Life)
            item_line ActualBudget "${dashboardIcons.actual-budget}"
            item_line Ghostfolio "${dashboardIcons.ghostfolio}"
            ;;
          Admin)
            item_line Grafana "${dashboardIcons.grafana}"
            item_line "AdGuard DNS" "${dashboardIcons.adguard-home}"
            item_line Arcane "${dashboardIcons.arcane}"
            ;;
        esac
      }

      open() {
        local subdomain="$1"
        exec chromium --app="https://$subdomain.$domain"
      }

      launch() {
        case "$1" in
          Jellyfin) open jellyfin ;;
          Navidrome) open navidrome ;;
          "Music Assistant") open ma ;;
          Sonarr) open sonarr ;;
          Radarr) open radarr ;;
          Lidarr) open lidarr ;;
          Bazarr) open bazarr ;;
          Prowlarr) open prowlarr ;;
          SABnzbd) open sabnzbd ;;
          Seerr) open seerr ;;
          Maintainerr) open maintainerr ;;
          Audiobookshelf) open audiobookshelf ;;
          Bookshelf) open bookshelf ;;
          "Home Assistant") open ha ;;
          Zigbee2MQTT) open z2m ;;
          Frigate) open nvr ;;
          ActualBudget) open actualbudget ;;
          Ghostfolio) open ghostfolio ;;
          Grafana) open grafana ;;
          "AdGuard DNS") open dns ;;
          Arcane) open oci ;;
        esac
      }

      group=$(group_lines | fuzzel --dmenu --icon-theme=AdwaitaLegacy --prompt="apps  ") || exit 0
      [ -z "$group" ] && exit 0

      item=$(items_for "$group" | fuzzel --dmenu --prompt="$group  ") || exit 0
      [ -z "$item" ] && exit 0

      launch "$item"
    '';
  };
in
{
  programs.niri = {
    enable = true;
    useNautilus = false;
  };

  programs.claude-desktop.enable = true;

  # Secret Service backend for Claude Desktop's credentials, auto-unlocked by PAM on TTY login.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;

  # Lets xdg-desktop-portal-gtk report dark-mode preference to Electron apps via dconf.
  programs.dconf.enable = true;

  # TTY theming isn't covered by home-manager's catppuccin bundle.
  catppuccin.tty.enable = true;

  # Needed for Chromium/Electron's --enable-wayland-ime + native Wayland windowing.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # Malayalam/Sanskrit via fcitx5 (Wayland support is built in; spawned in niri-config.kdl).
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = [ pkgs.fcitx5-m17n ];
    fcitx5.settings.inputMethod = {
      "Groups/0" = {
        Name = "Default";
        "Default Layout" = "us";
        DefaultIM = "keyboard-us";
      };
      "Groups/0/Items/0".Name = "keyboard-us";
      "Groups/0/Items/1".Name = "m17n_ml_swanalekha";
      "Groups/0/Items/2".Name = "m17n_sa_itrans";
      GroupOrder."0" = "Default";
    };
  };

  # Formalizes PipeWire, which was already running undeclared. pulse.enable backs waybar's
  # pulseaudio module; rtkit gives its threads realtime scheduling.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  home-manager.users.kra3 = {
    home.packages = [
      pkgs.swaybg
      pkgs.pwvucontrol # audio mixer, waybar pulseaudio right-click
      pkgs.bzmenu # bluetooth picker, Super+Alt+B in niri-config.kdl
      pkgs.pwmenu # audio device picker, Super+Alt+P in niri-config.kdl
      pkgs.wl-clipboard # wl-copy for the cliphist picker, Super+Alt+V in niri-config.kdl
      selfhostedMenu # self-hosted apps picker, Super+Alt+A in niri-config.kdl
      pkgs.adwaita-icon-theme-legacy # category icons for selfhosted-menu's group picker
    ];
    home.file.".local/share/wallpapers/wallpaper.png".source = ./wallpapers/wallpaper.png;

    # niri-session (not bare `niri`) is what imports the environment into systemd/D-Bus.
    home.shellAliases.wm = "niri-session";

    programs.alacritty.enable = true;
    # alacritty.toml is a read-only store symlink, so /terminal-setup can't patch it; declare
    # the Shift+Enter binding here instead.
    programs.alacritty.settings.keyboard.bindings = [
      { key = "Return"; mods = "Shift"; chars = "\n"; }
    ];
    programs.alacritty.settings.window.opacity = 0.96;
    programs.fuzzel.enable = true;
    programs.swaylock = {
      enable = true;
      # swaylock-effects for blur/clock/grace; catppuccin.swaylock's colors still merge in.
      package = pkgs.swaylock-effects;
      settings = {
        image = "/home/kra3/.local/share/wallpapers/wallpaper.png";
        effect-blur = "7x5";
        clock = true;
        fade-in = "0.2";
        grace = "2";
      };
    };

    programs.librewolf = {
      enable = true;
      profiles.default.isDefault = true;
    };
    catppuccin.librewolf.force = true;

    programs.chromium = {
      enable = true;
      package = pkgs.ungoogled-chromium;
    };

    # No catppuccin GTK module upstream; this just forces dark mode everywhere, including
    # Electron apps via the portal.
    gtk = {
      enable = true;
      theme = {
        name = "Adwaita";
        package = pkgs.gnome-themes-extra;
      };
      # GTK4 defaults to unthemed (null) rather than inheriting gtk.theme; pin it explicitly.
      gtk4.theme.name = "Adwaita";
      colorScheme = "dark";
    };

    programs.waybar = {
      enable = true;
      settings.mainBar = {
        layer = "top";
        position = "top";
        height = 30;
        modules-left = [
          "niri/workspaces"
          "niri/window"
        ];
        modules-center = [ "clock" ];
        modules-right = [
          "idle_inhibitor"
          "custom/nightlight"
          "network"
          "bluetooth"
          "pulseaudio"
          "load"
          "temperature"
          "disk"
          "memory"
          "cpu"
          "tray"
        ];

        "niri/window".max-length = 60;

        clock = {
          # timezones[0] (Copenhagen) is the primary display; sutala's own clock is UTC.
          format = "{:%Y-%m-%d %H:%M}";
          timezones = [
            "Europe/Copenhagen"
            "Asia/Kolkata"
            "America/Los_Angeles"
          ];
          timezone-tooltip-format = "{:%H:%M %Z}";
          tooltip-format = "<tt><small>{calendar}</small></tt>\n{tz_list}";
          calendar = {
            mode = "month";
            mode-mon-col = 3;
            weeks-pos = "left";
            # Pango <span> needs literal hex colors, not style.css's @-vars.
            format = {
              today = "<span color='#f38ba8'><b><u>{}</u></b></span>";
              months = "<span color='#b4befe'><b>{}</b></span>";
              weekdays = "<span color='#fab387'><b>{}</b></span>";
              weeks = "<span color='#7f849c'>{}</span>";
            };
          };
          actions = {
            on-click-right = "mode";
            on-scroll-up = "shift_up";
            on-scroll-down = "shift_down";
          };
        };

        # Toggles whether swayidle's timeouts below are allowed to fire.
        idle_inhibitor = {
          format = "{icon}";
          format-icons = {
            activated = "";
            deactivated = "";
          };
          tooltip-format-activated = "Idle inhibitor on — screen won't lock/sleep";
          tooltip-format-deactivated = "Idle inhibitor off — normal auto-lock/sleep";
        };

        # No built-in nightlight module; this toggles the wlsunset user service.
        "custom/nightlight" = {
          exec = ''systemctl --user is-active --quiet wlsunset.service && echo "" || echo ""'';
          on-click = "systemctl --user is-active --quiet wlsunset.service && systemctl --user stop wlsunset.service || systemctl --user start wlsunset.service";
          interval = 5;
          tooltip-format = "Night light (wlsunset) — click to toggle";
        };

        # No on-click toggle — enp2s0 carries DNS/media/Tailscale/SSH, so a misclick
        # shouldn't be able to cut remote access.
        network = {
          format-ethernet = "󰈀";
          format-wifi = "";
          format-disconnected = "";
          tooltip-format-ethernet = "{ifname}: {ipaddr}/{cidr}";
          tooltip-format-wifi = "{ifname}: {essid} ({signalStrength}%) — {ipaddr}/{cidr}";
          tooltip-format-disconnected = "Disconnected";
        };

        # Icon-only, detail lives in the tooltip; click toggles adapter power (BLE only).
        bluetooth = {
          format = "";
          format-disabled = "";
          format-off = "";
          tooltip-format = "{controller_alias}\n{status}";
          tooltip-format-connected = "{controller_alias}\n{status}\nConnected: {device_alias}";
          on-click = "bluetoothctl show | grep -q 'Powered: yes' && bluetoothctl power off || bluetoothctl power on";
        };

        pulseaudio = {
          format = "{icon} {volume}%";
          format-muted = "󰖁 {volume}%";
          format-icons = {
            default = [ "" "" ];
          };
          scroll-step = 5;
          on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          on-click-right = "pwvucontrol";
          tooltip-format = "{desc}: {volume}%";
        };

        load.format = " {load1}";

        # thermal-zone 1 is x86_pkg_temp (CPU package), not zone 0 (chassis).
        temperature = {
          thermal-zone = 1;
          format = " {temperatureC}°C";
          critical-threshold = 85;
          format-critical = " {temperatureC}°C";
        };

        disk = {
          path = "/";
          format = " {percentage_used}%";
        };

        # Adds a total, matching disk's default tooltip (memory's default omits it).
        memory = {
          format = "󰍛 {}%";
          tooltip-format = "{used:0.1f}GiB used out of {total:0.1f}GiB";
        };

        cpu.format = " {usage}%";
      };
      # catppuccin.waybar only defines @colors; this is what actually styles the bar.
      style = ''
        * {
          font-family: "FiraCode Nerd Font", sans-serif;
          font-size: 13px;
          border: none;
          border-radius: 0;
        }

        window#waybar {
          background-color: @base;
          color: @text;
        }

        #workspaces button {
          padding: 0 8px;
          color: @subtext0;
          background-color: transparent;
        }

        #workspaces button.active {
          color: @base;
          background-color: @blue;
          border-radius: 8px;
        }

        #clock,
        #tray,
        #niri-window,
        #idle_inhibitor,
        #custom-nightlight,
        #network,
        #bluetooth,
        #pulseaudio,
        #load,
        #temperature,
        #disk,
        #memory,
        #cpu {
          padding: 0 10px;
          color: @text;
        }

        #niri-window {
          color: @subtext0;
        }

        #idle_inhibitor {
          color: @lavender;
        }

        #idle_inhibitor.activated {
          color: @red;
        }

        #custom-nightlight {
          color: @yellow;
        }

        #network {
          color: @sky;
        }

        #bluetooth {
          color: @blue;
        }

        #bluetooth.disabled,
        #bluetooth.off {
          color: @overlay0;
        }

        #pulseaudio {
          color: @pink;
        }

        #pulseaudio.muted {
          color: @overlay0;
        }

        #load {
          color: @mauve;
        }

        #temperature {
          color: @peach;
        }

        #temperature.critical {
          color: @red;
        }

        #disk {
          color: @sapphire;
        }

        #memory {
          color: @green;
        }

        #cpu {
          color: @teal;
        }
      '';
    };

    services.mako.enable = true;
    services.cliphist.enable = true;
    services.polkit-gnome.enable = true;

    # Night-light; lat/long approximate Copenhagen since sutala's own tz is UTC.
    services.wlsunset = {
      enable = true;
      latitude = 55.7;
      longitude = 12.6;
    };

    # Locks after 1min idle, monitor off after 3min; no suspend — sutala keeps serving
    # DNS/media/home-assistant regardless of session lock state.
    services.swayidle = {
      enable = true;
      timeouts = [
        { timeout = 60; command = "${pkgs.swaylock-effects}/bin/swaylock -f"; }
        { timeout = 180; command = "niri msg action power-off-monitors"; }
      ];
    };

    catppuccin.cursors.enable = true;

    # niri ships no default config; this is the whole session (autostart, binds, etc).
    xdg.configFile."niri/config.kdl".source = ./niri-config.kdl;
  };
}
