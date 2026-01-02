{
  description = "kra3: NixOS configs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
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
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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

        imports = [ inputs.treefmt-nix.flakeModule ];

        perSystem =
          { pkgs, ... }:
          {
            treefmt.projectRootFile = "flake.nix";
            devShells.default = pkgs.mkShell {
              packages = [
                pkgs.age
                pkgs.colmena
                pkgs.just
                pkgs.nixos-rebuild
                pkgs.nixfmt-rfc-style
                pkgs.sops
                pkgs.ssh-to-age
              ];
            };
          };

        flake = {
          nixosConfigurations = {
            sutala = nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              specialArgs = { inputs = builtins.removeAttrs inputs [ "self" ]; };
              modules = [
                ./hosts/sutala/configuration.nix
              ];
            };
          };

          colmenaHive = inputs.colmena.lib.makeHive config.flake.colmena;
          colmena = {
            meta = {
              nixpkgs = import nixpkgs { system = "x86_64-linux"; };
              specialArgs = { inputs = builtins.removeAttrs inputs [ "self" ]; };
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
        };
      }
    );
}
