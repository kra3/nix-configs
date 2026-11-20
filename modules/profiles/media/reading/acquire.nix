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

      # The db password is still set centrally by postgresql-set-passwords in services/postgres.nix.
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
