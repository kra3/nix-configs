{
  description = "kra3: NixOS configs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    declarative-jellyfin = {
      url = "github:Sveske-Juice/declarative-jellyfin";
    };

    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    quadlet-nix = {
      url = "github:SEIAROTg/quadlet-nix";
    };

    llm-agents.url = "github:numtide/llm-agents.nix";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin = {
      url = "github:catppuccin/nix/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-desktop-nix-flake = {
      url = "github:poeck/claude-desktop-nix-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mcp-nixos.url = "github:utensils/mcp-nixos";
  };

  outputs =
    inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { config, ... }:
      {
        systems = [
          "aarch64-darwin"
          "aarch64-linux"
          "x86_64-linux"
        ];

        imports = [
          inputs.treefmt-nix.flakeModule
        ];

        perSystem =
          { pkgs, inputs', ... }:
          {
            treefmt.projectRootFile = "flake.nix";
            devShells.default = pkgs.mkShell {
              packages = [
                pkgs.age
                inputs'.colmena.packages.colmena
                pkgs.just
                pkgs.nixos-rebuild
                pkgs.nixfmt
                pkgs.sops
                pkgs.ssh-to-age
              ];
              shellHook = ''
                unset PROMPT_COMMAND
              '';
            };
          };

        flake =
          let
            inherit (nixpkgs) lib;
            hosts = import ./flake/hosts.nix { inherit inputs; };
            ofClass = class: lib.filterAttrs (_: h: h.class == class) hosts;
            buildEach =
              builder: hostSet:
              lib.mapAttrs (
                _: h: builder { inherit (h) modules; specialArgs = { inherit inputs; }; }
              ) hostSet;
          in
          {
            overlays.default = import ./modules/overlays;

            nixosConfigurations = buildEach nixpkgs.lib.nixosSystem (ofClass "nixos");
            darwinConfigurations = buildEach inputs.nix-darwin.lib.darwinSystem (ofClass "darwin");

            colmenaHive = inputs.colmena.lib.makeHive config.flake.colmena;
            colmena = {
              meta = {
                # No overlays here: hosts.sutala.modules (reused verbatim below)
                # already carries `{ nixpkgs.overlays = [...]; }`. Setting it again
                # here would make the node apply the overlay twice (once via this
                # prebuilt pkgs' nixpkgsModule, once via the reused module list).
                nixpkgs = import nixpkgs { inherit (hosts.sutala) system; };
                specialArgs = { inputs = inputs; };
              };
              sutala = {
                deployment = hosts.sutala.deployment;
                imports = hosts.sutala.modules ++ [
                  {
                    # Colmena builds each node via nixpkgs' nixos/lib/eval-config.nix
                    # directly (src/nix/hive/eval.nix), bypassing the flake's own
                    # `nixosSystem` wrapper. That wrapper is what normally injects the
                    # flake-extended `lib` (nixpkgs's own lib/flake-version-info.nix
                    # overlay, only present on the `nixpkgs.lib` flake output) which
                    # stamps `system.nixos.versionSuffix`/`system.nixos.revision` from
                    # self.lastModifiedDate/self.shortRev/self.rev. Without it, colmena
                    # falls back to eval-config.nix's plain `lib ? import ../../lib`,
                    # whose versionSuffix is always "pre-git" and revision always null
                    # -- the actual cause of colmenaHive.nodes.sutala's drvPath
                    # diverging from nixosConfigurations.sutala's (it also changes the
                    # `nixos-version` package embedded in environment.systemPackages,
                    # since it bakes in `config.system.nixos.revision`). Reproduce both
                    # effects explicitly so this node's drv converges.
                    nixpkgs.flake.source = inputs.nixpkgs.outPath;
                    system.nixos.versionSuffix = inputs.nixpkgs.lib.trivial.versionSuffix;
                    system.nixos.revision = inputs.nixpkgs.lib.trivial.revisionWithDefault null;
                  }
                ];
              };
            };
          };
      }
    );
}
