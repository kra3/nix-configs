{ lib, pkgs, ... }:
{
  systemd.tmpfiles.rules = [
    "d /srv/databases 0755 root root - -"
    "d /srv/databases/postgresql 0700 postgres postgres - -"
  ];

  services.postgresql = {
    enable = true;
    dataDir = "/srv/databases/postgresql";
    settings.listen_addresses = lib.mkForce "*";
    ensureDatabases = [ "firefly" ];
    ensureUsers = [
      {
        name = "firefly";
        ensureDBOwnership = true;
        ensureClauses = {
          login = true;
        };
      }
    ];
    authentication = lib.mkOverride 10 ''
      # firefly app connects from br-life (host.containers.internal) without password
      host firefly firefly 10.0.0.0/8 trust
      # all other local socket connections use peer (OS user must match pg user)
      local all all peer
      # loopback TCP for manual access
      host all all 127.0.0.1/32 scram-sha-256
    '';
  };

  # allow containers on br-life to reach postgresql
  networking.firewall.interfaces.br-life.allowedTCPPorts = [ 5432 ];
}

