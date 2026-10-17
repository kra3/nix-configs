{ self, ... }:
{
  perSystem =
    { lib, pkgs, ... }:
    let
      pins = self.lib.ha-pins pkgs;
      prefixed = group: lib.mapAttrs' (name: drv: lib.nameValuePair "${group}-${name}" drv) pins.${group};
    in
    {
      packages.ha-pins = pkgs.linkFarm "ha-pins" (prefixed "integrations" // prefixed "frontend");
    };
}
