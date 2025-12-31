{
  description = "kra3: NixOS configs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      disko,
      colmena,
      ...
    }:
    {
      nixosConfigurations = {
        sutala = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/sutala/configuration.nix
            home-manager.nixosModules.home-manager
            disko.nixosModules.disko
          ];
        };
      };

      colmenaHive = colmena.lib.makeHive self.outputs.colmena;
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
            imports = [
              ./hosts/sutala/configuration.nix
              home-manager.nixosModules.home-manager
              disko.nixosModules.disko
            ];
          };
      };
    };
}
