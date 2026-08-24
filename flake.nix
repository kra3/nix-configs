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

    mcp-nixos.url = "github:utensils/mcp-nixos";
  };

  outputs =
    inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { config, ... }:
      {
        systems = [
          "aarch64-darwin"
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
                pkgs.nixfmt-rfc-style
                pkgs.sops
                pkgs.ssh-to-age
              ];
              shellHook = ''
                unset PROMPT_COMMAND
              '';
            };
          };

        flake = {
          overlays.default = import ./modules/overlays;
          
          nixosConfigurations = {
            sutala = nixpkgs.lib.nixosSystem {
              specialArgs = { inputs = inputs; };
              modules = [
                { nixpkgs.hostPlatform = "x86_64-linux"; }
                { nixpkgs.overlays = [ inputs.self.overlays.default ]; }
                ./hosts/sutala/configuration.nix
              ];
            };
          };

          colmenaHive = inputs.colmena.lib.makeHive config.flake.colmena;
          colmena = {
            meta = {
              nixpkgs = import nixpkgs {
                system = "x86_64-linux";
                overlays = [ inputs.self.overlays.default ];
              };
              specialArgs = { inputs = inputs; };
            };
            sutala =
              { ... }:
              {
                deployment = {
                  targetHost = "sutala-root";
                  targetUser = "root";
                  buildOnTarget = true;
                };
                imports = [
                  ./hosts/sutala/configuration.nix
                ];
              };
          };

          darwinConfigurations.mac-work = inputs.nix-darwin.lib.darwinSystem {
            system = "aarch64-darwin";
            specialArgs = { inputs = inputs; };
            modules = [
              { nixpkgs.overlays = [ inputs.self.overlays.default ]; }
              inputs.home-manager.darwinModules.home-manager
              ./hosts/mac-work
            ];
          };
        };
      }
    );
}
