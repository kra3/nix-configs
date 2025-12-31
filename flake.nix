{
  description = "kra3: NixOS configs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
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
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
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
                pkgs.nixfmt-rfc-style
                pkgs.sops
              ];
            };
          };

        flake = {
          nixosConfigurations = {
            sutala = nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              specialArgs = { inherit inputs; };
              modules = [
                ./hosts/sutala/configuration.nix
              ];
            };
          };

          colmenaHive = inputs.colmena.lib.makeHive config.flake.colmena;
          colmena = {
            meta = {
              nixpkgs = import nixpkgs { system = "x86_64-linux"; };
            };
            sutala =
              { ... }:
              {
                deployment = {
                  targetHost = "sutala-root";
                  targetUser = "root";
                  buildOnTarget = true;
                };
                specialArgs = { inherit inputs; };
                imports = [
                  ./hosts/sutala/configuration.nix
                ];
              };
          };
        };
      }
    );
}
