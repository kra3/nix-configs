{
  flake.nixosModules.services-niri-default =
    { inputs, pkgs, ... }:
    {
      programs.niri = {
        enable = true;
        useNautilus = false;
      };

      environment.systemPackages = [ inputs.llm-agents.packages.${pkgs.system}.claude-desktop ];

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
        fcitx5.waylandFrontend = true;
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
    };
}
