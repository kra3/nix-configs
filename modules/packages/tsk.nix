{ inputs, ... }:
{
  perSystem =
    { lib, pkgs, ... }:
    {
      packages.tsk = pkgs.rustPlatform.buildRustPackage {
        pname = "tsk";
        version = (lib.importTOML (inputs.tsk + "/Cargo.toml")).package.version;
        src = inputs.tsk;
        cargoLock.lockFile = inputs.tsk + "/Cargo.lock";
        doCheck = false;

        meta.mainProgram = "tsk";
      };
    };
}
