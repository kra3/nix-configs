{
  description = "kra3: NixOS configs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:denful/import-tree";

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

    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";

    # rtk isn't packaged in a stable nixpkgs channel yet (only nixpkgs-unstable); switch to that once it graduates.
    rtk-nix = {
      url = "github:farwydi/rtk-nix";
      flake = false;
    };
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
          (inputs.import-tree ./modules)
        ];

        perSystem =
          { pkgs, ... }:
          {
            treefmt.projectRootFile = "flake.nix";
            devShells.default = pkgs.mkShell {
              packages = [
                pkgs.age
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
                _: h:
                builder {
                  inherit (h) modules;
                  specialArgs = {
                    inherit inputs;
                    # Their board modules destructure `nixos-raspberrypi` directly, not via `inputs`.
                    nixos-raspberrypi = inputs.nixos-raspberrypi;
                    flakeModules = {
                      nixos = config.flake.nixosModules;
                      darwin = config.flake.darwinModules;
                      homeManager = config.flake.homeManagerModules;
                    };
                    flakeLib = config.flake.lib;
                  };
                }
              ) hostSet;
          in
          {
            # `overlays.default` writes into the same `config.flake.overlays`
            # attrset that every individually-registered overlay file writes
            # into, so composing "all of config.flake.overlays" would include
            # this value's own (not-yet-computed) result. Excluding "default"
            # breaks that self-reference.
            overlays.default = lib.composeManyExtensions (
              builtins.attrValues (builtins.removeAttrs config.flake.overlays [ "default" ])
            );

            nixosConfigurations = buildEach nixpkgs.lib.nixosSystem (ofClass "nixos");
            darwinConfigurations = buildEach inputs.nix-darwin.lib.darwinSystem (ofClass "darwin");
          };
      }
    );
}
