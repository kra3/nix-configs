{
  flake.nixosModules.profiles-finance-investments =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.profiles-life-shared
        flakeModules.nixos.containers-life-ghostfolio-default
        flakeModules.nixos.services-postgres
        flakeModules.nixos.services-redis
      ];

      # The db password is still set centrally by postgresql-set-passwords in services/postgres.nix.
      services.postgresql.ensureDatabases = [ "ghostfolio" ];
      services.postgresql.ensureUsers = [
        {
          name = "ghostfolio";
          ensureDBOwnership = true;
          ensureClauses = {
            login = true;
          };
        }
      ];
    };
}
