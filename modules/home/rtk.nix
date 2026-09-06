{
  flake.homeManagerModules.home-rtk = { inputs, pkgs, ... }: {
    home.packages = [ (pkgs.callPackage "${inputs.rtk-nix}/package.nix" { }) ];
  };
}
