{
  flake.homeManagerModules.home-jankyborders = { pkgs, ... }: {
    home.packages = [ pkgs.jankyborders ];

    launchd.agents.jankyborders = {
      enable = true;
      config = {
        ProgramArguments = [
          "${pkgs.jankyborders}/bin/borders"
          # Catppuccin mocha blue (matches catppuccin.accent) / surface1.
          "active_color=glow(0xff89b4fa)"
          "inactive_color=0xff313244"
          "width=4.0"
          "style=round"
        ];
        RunAtLoad = true;
        KeepAlive = true;
      };
    };
  };
}
