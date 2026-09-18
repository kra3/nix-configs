{
  flake.homeManagerModules.home-jankyborders = { pkgs, ... }: {
    home.packages = [ pkgs.jankyborders ];

    launchd.agents.jankyborders = {
      enable = true;
      config = {
        ProgramArguments = [
          "${pkgs.jankyborders}/bin/borders"
          "active_color=glow(0xff00ffaa)"
          "inactive_color=0xff313244"
          "width=6.0"
          "style=round"
        ];
        RunAtLoad = true;
        KeepAlive = true;
      };
    };
  };
}
