{
  flake.nixosModules.profiles-media-reading-acquire =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.profiles-media-shared
        flakeModules.nixos.containers-media-mgmt-bookshelf
        flakeModules.nixos.containers-media-mgmt-rreading-glasses
        flakeModules.nixos.services-postgres
      ];

      services.postgresql.ensureDatabases = [ "rreading_glasses" ];
      services.postgresql.ensureUsers = [
        {
          name = "rreading_glasses";
          ensureDBOwnership = true;
          ensureClauses = {
            login = true;
          };
        }
      ];
    };
}
