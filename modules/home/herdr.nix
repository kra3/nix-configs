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
        keys.prefix = "ctrl+a";
      };

      home.file.".claude/skills/herdr/SKILL.md".source =
        pkgs.runCommand "herdr-skill.md" { }
          "${herdr}/bin/herdr --skill > $out";
    };
}
