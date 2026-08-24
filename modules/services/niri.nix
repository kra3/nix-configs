{ pkgs, ... }:
{
  programs.niri = {
    enable = true;
    useNautilus = false;
  };

  services.gnome.gnome-keyring.enable = false;

  home-manager.users.kra3 = {
    home.packages = [ pkgs.swaybg ];

    programs.alacritty.enable = true;
    programs.fuzzel.enable = true;
    programs.swaylock.enable = true;

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
