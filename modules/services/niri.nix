{ pkgs, config, ... }:
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

  # Chromium/Electron's nixpkgs wrapper only adds --enable-wayland-ime (and native Wayland
  # windowing) when this is set — without it, ibus silently doesn't work in Chromium-based
  # apps (Claude Desktop included) even though niri is Wayland-only.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # Malayalam/Sanskrit via ibus. waylandFrontend stays at its default (false), which is what
  # auto-exports GTK_IM_MODULE/QT_IM_MODULE for GTK/Qt apps; native-Wayland apps (Alacritty)
  # get ibus separately via the ibus-wayland spawn in niri-config.kdl.
  i18n.inputMethod = {
    enable = true;
    type = "ibus";
    ibus.engines = [ pkgs.ibus-engines.m17n ];
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

    # Preloads ibus engines + sets the Ctrl+Space switch hotkey so it works right after
    # switch. Real engine IDs: `ibus engine --list-engine`.
    dconf.settings = {
      "org/freedesktop/ibus/general" = {
        preload-engines = [
          "xkb:us::eng"
          "m17n:ml:swanalekha"
          "m17n:sa:itrans"
        ];
        engines-order = [
          "xkb:us::eng"
          "m17n:ml:swanalekha"
          "m17n:sa:itrans"
        ];
      };
      "org/freedesktop/ibus/general/hotkey" = {
        triggers = [ "<Control>space" ];
      };
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
          "custom/ibus"
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

        # Short engine code in the bar; full name + Ctrl+Space hint in the tooltip.
        "custom/ibus" = {
          exec = ''
            engine=$(ibus engine 2>/dev/null)
            case "$engine" in
              xkb:us::eng)
                short=us; name="English (US)" ;;
              m17n:ml:swanalekha)
                short=ml; name="Malayalam (Swanalekha)" ;;
              m17n:sa:itrans)
                short=skt; name="Sanskrit (ITRANS)" ;;
              *)
                short="$engine"; name="$engine" ;;
            esac
            printf '{"text":"%s","tooltip":"%s — Ctrl+Space to cycle"}' "$short" "$name"
          '';
          return-type = "json";
          interval = 1;
          format = " {}";
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
        #custom-ibus,
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
    # @ibus-wayland@ is substituted with the real store path (see niri-config.kdl).
    xdg.configFile."niri/config.kdl".text = builtins.replaceStrings
      [ "@ibus-wayland@" ]
      [ "${config.i18n.inputMethod.package}/libexec/ibus-wayland" ]
      (builtins.readFile ./niri-config.kdl);
  };
}
