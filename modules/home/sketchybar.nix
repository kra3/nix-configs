{
  flake.homeManagerModules.home-sketchybar = { pkgs, ... }: {
    home.packages = [ pkgs.sketchybar ];

    xdg.configFile = {
      "sketchybar/sketchybarrc".source = ./sketchybar/sketchybarrc;
      "sketchybar/plugins/aerospace.sh".source = ./sketchybar/plugins/aerospace.sh;
      "sketchybar/plugins/battery.sh".source = ./sketchybar/plugins/battery.sh;
      "sketchybar/plugins/clock.sh".source = ./sketchybar/plugins/clock.sh;
      "sketchybar/plugins/cpu.sh".source = ./sketchybar/plugins/cpu.sh;
      "sketchybar/plugins/front_app.sh".source = ./sketchybar/plugins/front_app.sh;
      "sketchybar/plugins/memory.sh".source = ./sketchybar/plugins/memory.sh;
      "sketchybar/plugins/mic.sh".source = ./sketchybar/plugins/mic.sh;
      "sketchybar/plugins/network.sh".source = ./sketchybar/plugins/network.sh;
      "sketchybar/plugins/volume.sh".source = ./sketchybar/plugins/volume.sh;
    };

    launchd.agents.sketchybar = {
      enable = true;
      config = {
        ProgramArguments = [ "${pkgs.sketchybar}/bin/sketchybar" ];
        RunAtLoad = true;
        KeepAlive = true;
        # launchd's minimal PATH lacks sketchybar/aerospace; plugins call them bare.
        EnvironmentVariables.PATH = "${pkgs.sketchybar}/bin:${pkgs.aerospace}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };
  };
}
