{ ... }:
{
  programs.niri = {
    enable = true;
    useNautilus = false;
  };

  xdg.portal.enable = false;
  services.gnome.gnome-keyring.enable = false;

  home-manager.users.kra3 = {
    programs.alacritty.enable = true;
    programs.fuzzel.enable = true;

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
    };
  };
}
