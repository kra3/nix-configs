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
  };
}
