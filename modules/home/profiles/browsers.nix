{
  flake.homeManagerModules.home-profiles-browsers = { pkgs, ... }: {
    programs.librewolf = {
      enable = true;
      profiles.default.isDefault = true;
    };
    catppuccin.librewolf.force = true;

    programs.chromium = {
      enable = true;
      package = pkgs.ungoogled-chromium;
    };

    # xdg-open has no default browser without this, so apps that shell out to it
    # (e.g. Picard's "Lookup in Browser") silently do nothing.
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = "librewolf.desktop";
        "x-scheme-handler/http" = "librewolf.desktop";
        "x-scheme-handler/https" = "librewolf.desktop";
        "x-scheme-handler/about" = "librewolf.desktop";
        "x-scheme-handler/unknown" = "librewolf.desktop";
      };
    };
  };
}
