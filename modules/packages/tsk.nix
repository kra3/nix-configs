{
  perSystem =
    { pkgs, ... }:
    {
      packages.tsk = pkgs.rustPlatform.buildRustPackage (finalAttrs: {
        pname = "tsk";
        version = "0.11.6";

        src = pkgs.fetchFromGitHub {
          owner = "smarzban";
          repo = "tsk";
          tag = "v${finalAttrs.version}";
          hash = "sha256-nkuCSQg6C1EVVYTdXdLDZV+TT0Xdu93kTV/LgBJEwGQ=";
        };

        cargoHash = "sha256-FMCxgtHvra3AYwL0M2s8x5XbYaLXRGRk1oZ8ezq51Js=";
        doCheck = false;

        meta.mainProgram = "tsk";
      });
    };
}
