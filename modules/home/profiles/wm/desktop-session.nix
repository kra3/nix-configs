{
  flake.homeManagerModules.home-profiles-wm-desktop-session =
  { pkgs, lib, config, domain, ... }:
  # domain is threaded from hosts/sutala/configuration.nix's home-manager.extraSpecialArgs
  let
    cliphistPkg = config.services.cliphist.package;
    wlClipboardPkg = config.services.cliphist.clipboardPackage;
    cliphistExtraOptions = lib.escapeShellArgs config.services.cliphist.extraOptions;

    # KeePassXC/Bitwarden/1Password tag password copies with this MIME hint; wl-paste
    # itself doesn't know about it, so drop those events before they reach cliphist store.
    cliphist-store-filtered = pkgs.writeShellApplication {
      name = "cliphist-store-filtered";
      runtimeInputs = [
        wlClipboardPkg
        cliphistPkg
        pkgs.gnugrep
      ];
      text = ''
        if wl-paste --list-types | grep -qx 'x-kde-passwordManagerHint'; then
          cat >/dev/null
          exit 0
        fi
        exec cliphist ${cliphistExtraOptions} store
      '';
    };

    # Super+Alt+V picker: ranks cliphist's history by picker-selection count (most-used
    # first), falling back to cliphist's own id (most recent first) for ties/unused items.
    # Runs in a terminal (fzf, not rofi/fuzzel) so it gets fzf's live preview pane — no
    # dmenu-protocol tool (dmenu, rofi -dmenu, wofi, bemenu, tofi, fuzzel) supports one.
    cliphist-picker = pkgs.writeShellApplication {
      name = "cliphist-picker";
      runtimeInputs = [
        cliphistPkg
        pkgs.gawk
        pkgs.fzf
        wlClipboardPkg
      ];
      text = ''
        usage_file="''${XDG_STATE_HOME:-$HOME/.local/state}/cliphist/usage.tsv"
        mkdir -p "$(dirname "$usage_file")"
        touch "$usage_file"

        selection=$(
          cliphist list \
            | awk -F'\t' -v OFS='\t' '
                ARGIND == 1 { count[$2] = $1; next }
                { print ($2 in count ? count[$2] : 0), $1, $2 }
              ' "$usage_file" - \
            | sort -t $'\t' -k1,1nr -k2,2nr \
            | cut -f2- \
            | fzf --delimiter=$'\t' --with-nth=2 \
                --preview='cliphist decode {1}' --preview-window=bottom:60%:wrap \
                --prompt='Clipboard> '
        )

        [ -n "$selection" ] || exit 0

        id=''${selection%%$'\t'*}
        preview=''${selection#*$'\t'}

        cliphist decode "$id" | wl-copy

        awk -F'\t' -v OFS='\t' -v target="$preview" '
          $2 == target { print $1 + 1, $2; found = 1; next }
          { print }
          END { if (!found) print 1, target }
        ' "$usage_file" > "$usage_file.tmp"
        mv "$usage_file.tmp" "$usage_file"
      '';
    };

    # Custom rofi script mode: type a query, Enter opens it on DuckDuckGo.
    # Protocol: https://github.com/davatorium/rofi/blob/next/doc/rofi-script.5.markdown
    rofi-websearch = pkgs.writeShellApplication {
      name = "rofi-websearch";
      runtimeInputs = [
        pkgs.jq
        pkgs.xdg-utils
      ];
      text = ''
        query="''${1:-}"
        if [ -n "$query" ]; then
          encoded=$(printf '%s' "$query" | jq -sRr @uri)
          xdg-open "https://duckduckgo.com/?q=$encoded" >/dev/null 2>&1 &
          exit 0
        fi
        echo "Type a search query and press Enter"
      '';
    };

    # Custom rofi script mode: "<amount> <FROM> <TO>" (e.g. "100 usd eur"), Enter shows the
    # converted amount as a result row; Enter again copies just the number to the clipboard.
    rofi-currency = pkgs.writeShellApplication {
      name = "rofi-currency";
      runtimeInputs = [
        pkgs.curl
        pkgs.jq
        pkgs.gnused
        wlClipboardPkg
      ];
      text = ''
        query="''${1:-}"

        if [[ "$query" =~ ^([0-9.]+)\ ([A-Za-z]{3})\ =\ ([0-9.]+)\ ([A-Za-z]{3})$ ]]; then
          printf '%s' "''${BASH_REMATCH[3]}" | wl-copy
          exit 0
        fi

        if [ -z "$query" ]; then
          echo "Type: <amount> <FROM> <TO>, e.g. 100 usd eur"
          exit 0
        fi

        read -r amount from to _ <<<"$(echo "$query" | sed -E 's/\bto\b//I')"
        from=''${from^^}
        to=''${to^^}

        if ! [[ "$amount" =~ ^[0-9.]+$ ]] || [ -z "$from" ] || [ -z "$to" ]; then
          echo "Format: <amount> <FROM> <TO>, e.g. 100 usd eur"
          exit 0
        fi

        result=$(curl -s "https://api.frankfurter.dev/v1/latest?amount=$amount&from=$from&to=$to" | jq -r --arg to "$to" '.rates[$to] // "error"')

        if [ "$result" = "error" ] || [ -z "$result" ]; then
          echo "Couldn't convert $from to $to — check the currency codes"
          exit 0
        fi

        echo "$amount $from = $result $to"
      '';
    };
  in
  {
    home.packages = [
      pkgs.swaybg
      pkgs.pwvucontrol # audio mixer, waybar pulseaudio right-click
      pkgs.bzmenu # bluetooth picker, Super+Alt+B in niri-config.kdl
      pkgs.pwmenu # audio device picker, Super+Alt+P in niri-config.kdl
      pkgs.wl-clipboard # wl-copy/wl-paste general CLI use
      cliphist-picker # Super+Alt+V in niri-config.kdl
    ];
    home.file.".local/share/wallpapers/wallpaper.png".source = ./wallpapers/wallpaper.png;

    # Single entry point for every self-hosted app, behind Authelia SSO; shows up
    # in the regular rofi app launcher (Mod+D) instead of a dedicated picker.
    xdg.desktopEntries.homepage-dashboard = {
      name = "Home Page";
      genericName = "Self-hosted apps dashboard";
      exec = ''chromium --app="https://home.${domain}"'';
      icon = "start-here";
      terminal = false;
      categories = [ "Network" ];
    };

    programs.rofi = {
      enable = true;
      package = pkgs.rofi.override {
        plugins = [
          pkgs.rofi-calc
          pkgs.rofi-file-browser
        ];
      };
      # Mod+D opens on "drun"; Tab/Shift+Tab cycle the rest of this list inline
      # (rofi's built-in mode-switcher) instead of needing a keybind per mode.
      modes = [
        "drun"
        "window"
        "run"
        "ssh"
        "calc"
        "filebrowser"
        {
          name = "websearch";
          path = "${rofi-websearch}/bin/rofi-websearch";
        }
        {
          name = "currency";
          path = "${rofi-currency}/bin/rofi-currency";
        }
      ];
    };
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
    # 500 items of unranked history is unusable; 50 keeps the picker relevant, and
    # dedupe-search matches it so a duplicate anywhere in history is caught, not just recent ones.
    services.cliphist.extraOptions = [
      "-max-dedupe-search"
      "50"
      "-max-items"
      "50"
    ];
    # Route both watchers through the password-manager-hint filter above.
    systemd.user.services.cliphist.Service.ExecStart =
      lib.mkForce "${wlClipboardPkg}/bin/wl-paste --watch ${cliphist-store-filtered}/bin/cliphist-store-filtered";
    systemd.user.services.cliphist-images.Service.ExecStart =
      lib.mkForce "${wlClipboardPkg}/bin/wl-paste --type image --watch ${cliphist-store-filtered}/bin/cliphist-store-filtered";
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
  };
}
