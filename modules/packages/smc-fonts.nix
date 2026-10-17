{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        inherit (pkgs.extend self.overlays.smc-malayalam-fonts)
          smc-meera
          smc-rachana
          smc-anjalioldlipi
          smc-karumbi
          ;
      };
    };
}
