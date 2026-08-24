{ pkgs, ... }:
{
  programs.niri = {
    enable = true;
    useNautilus = false;
  };

  programs.claude-desktop.enable = true;

  # Needed for apps like Claude Desktop to store credentials via the
  # Secret Service API. Auto-unlocked with the login password on the
  # console (niri is started manually after a TTY login, so PAM service
  # "login" is what actually authenticates — not "sshd").
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;

  # Home-manager's gtk module writes theme/color-scheme into dconf so
  # xdg-desktop-portal-gtk can report "prefer-dark" to apps (Electron
  # apps like Claude Desktop query this instead of reading GTK settings
  # directly). Requires the system dconf service to actually exist.
  programs.dconf.enable = true;

  # Catppuccin Mocha for the Linux virtual console (only home-manager's
  # bundle of catppuccin modules is imported by default; this NixOS-level
  # one needs its own theming module enabled).
  catppuccin.tty.enable = true;

  home-manager.users.kra3 = {
    home.packages = [ pkgs.swaybg ];

    programs.alacritty.enable = true;
    programs.fuzzel.enable = true;
    programs.swaylock.enable = true;

    programs.librewolf = {
      enable = true;
      profiles.default.isDefault = true;
    };
    catppuccin.librewolf.force = true;

    programs.chromium = {
      enable = true;
      package = pkgs.ungoogled-chromium;
    };

    # catppuccin/nix dropped its GTK theme module (upstream catppuccin/gtk
    # was archived), so there's no themed GTK stylesheet to pull in here —
    # this just forces every GTK app (and, via the portal, Electron apps
    # like Claude Desktop) into dark mode to match the rest of the
    # Catppuccin Mocha setup.
    gtk = {
      enable = true;
      theme = {
        name = "Adwaita";
        package = pkgs.gnome-themes-extra;
      };
      # GTK4 theming is unsupported upstream and defaults to null instead of
      # inheriting gtk.theme from 26.05 on; pin it explicitly so GTK4 apps
      # stay dark too instead of silently drifting to their own default.
      gtk4.theme.name = "Adwaita";
      colorScheme = "dark";
    };

    programs.waybar = {
      enable = true;
      settings.mainBar = {
        layer = "top";
        position = "top";
        height = 30;
        modules-left = [ "niri/workspaces" ];
        modules-center = [ "clock" ];
        modules-right = [ "tray" ];
        clock.format = "{:%Y-%m-%d %H:%M}";
      };
      # catppuccin.waybar only prepends `@import ".../mocha.css"`, which merely
      # defines `@define-color` variables — it sets no selectors itself, so the
      # bar stays GTK-default (white) without this to consume them.
      style = ''
        * {
          font-family: sans-serif;
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
        #tray {
          padding: 0 10px;
          color: @text;
        }
      '';
    };

    services.mako.enable = true;
    services.cliphist.enable = true;
    services.polkit-gnome.enable = true;

    # Locks after 1min idle, powers off the monitor ~2min after that.
    # No suspend/hibernate action — sutala has to keep serving DNS/media/
    # home-assistant regardless of screen or session lock state.
    services.swayidle = {
      enable = true;
      timeouts = [
        { timeout = 60; command = "${pkgs.swaylock}/bin/swaylock -f"; }
        { timeout = 180; command = "niri msg action power-off-monitors"; }
      ];
    };

    catppuccin.cursors.enable = true;

    # niri ships no config by default; this is the whole session definition —
    # autostart, idle-lock keybind, launcher/terminal binds, clipboard picker.
    xdg.configFile."niri/config.kdl".source = ./niri-config.kdl;
  };
}
