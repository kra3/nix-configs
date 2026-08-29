{
  flake.nixosModules.services-finance-ghostfolio-backfill = { config, pkgs, ... }:
  let
    scraperPython = pkgs.python3.withPackages (ps: [ ps.requests ps.psycopg2 ]);
    scraperScript = ./scraper/scraper.py;
    symbolsConfig = ./scraper/symbols.json;
  in
  {
    systemd.services.ghostfolio-scraper-backfill = {
      description = "Backfill Ghostfolio market data (6 years)";
      after = [ "postgresql.service" "postgresql-set-passwords.service" ];
      requires = [ "postgresql.service" "postgresql-set-passwords.service" ];
      serviceConfig = {
        Type = "oneshot";
        Restart = "no";
        EnvironmentFile = config.sops.templates."life.ghostfolio-scraper.env".path;
        ExecStart = "${scraperPython}/bin/python ${scraperScript} --backfill --config ${symbolsConfig}";
        User = "ghostfolio-scraper";
        Group = "life";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    systemd.timers.ghostfolio-scraper-backfill = {
      description = "Backfill Ghostfolio market data yearly";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "yearly";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };
}
