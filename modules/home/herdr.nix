{
  flake.homeManagerModules.home-herdr =
    { inputs, pkgs, ... }:
    let
      herdr = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.herdr;
    in
    {
      home.packages = [ herdr ];

      # herdr rewrites this file for onboarding and the Settings UI; those writes fail on the read-only symlink, so change it here.
      xdg.configFile."herdr/config.toml".source = (pkgs.formats.toml { }).generate "herdr-config.toml" {
        onboarding = false;
        keys = {
          prefix = "ctrl+a";
          detach = "prefix+d";
          last_pane = "prefix+;";
          rename_tab = "prefix+comma";
          split_vertical = "prefix+|";
          split_horizontal = "prefix+minus";
          resize_pane_left = "prefix+shift+h";
          resize_pane_down = "prefix+shift+j";
          resize_pane_up = "prefix+shift+k";
          resize_pane_right = "prefix+shift+l";
          reload_config = "prefix+r";
          resize_mode = "prefix+shift+r";
        };
        experimental.pane_history = true;
      };

      home.file.".claude/skills/herdr/SKILL.md".source =
        pkgs.runCommand "herdr-skill.md" { }
          "${herdr}/bin/herdr --skill > $out";
    };
}
