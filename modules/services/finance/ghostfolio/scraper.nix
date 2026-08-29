{
  flake.nixosModules.services-finance-ghostfolio-scraper = { config, lib, pkgs, flakeLib, ... }:
  let
    scraperPython = pkgs.python3.withPackages (ps: [ ps.requests ps.psycopg2 ]);
    scraperScript = ./scraper/scraper.py;
    symbolsConfig = ./scraper/symbols.json;
  in
  {
    users.users.ghostfolio-scraper = {
      isSystemUser = true;
      group = "life";
    };

    sops.templates."life.ghostfolio-scraper.env" = {
      owner = "root";
      group = "life";
      mode = "0440";
      content = ''
        DATABASE_URL=postgresql://ghostfolio:${config.sops.placeholder."db.ghostfolio_password"}@localhost:5432/ghostfolio
      '';
    };

    systemd.services.ghostfolio-scraper = {
      description = "Scrape latest Ghostfolio market data";
      after = [ "postgresql.service" "postgresql-set-passwords.service" ];
      requires = [ "postgresql.service" "postgresql-set-passwords.service" ];
      serviceConfig = {
        Type = "oneshot";
        Restart = "no";
        EnvironmentFile = config.sops.templates."life.ghostfolio-scraper.env".path;
        ExecStart = "${scraperPython}/bin/python ${scraperScript} --config ${symbolsConfig}";
        User = "ghostfolio-scraper";
        Group = "life";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    systemd.timers.ghostfolio-scraper = {
      description = "Run Ghostfolio market data scraper daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    };

    environment.etc."alloy/ghostfolio-scraper.alloy".text = flakeLib.observability.mkAlloyJournalSource {
      name = "ghostfolio-scraper";
      id = "ghostfolio_scraper";
      hostName = config.networking.hostName;
    };
  };
}
