{
  flake.nixosModules.services-system-chromium =
    { config, ... }:
    {
      programs.chromium = {
        enable = true;
        homepageLocation = "https://home.${config.vars.acme.domain}";
      };
    };
}
