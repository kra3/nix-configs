{ ... }:
{
  systemd.tmpfiles.rules = [
    "d /srv/databases/redis 0700 redis redis - -"
  ];

  # bind 0.0.0.0 like postgres (listen_addresses = "*") — firewall restricts
  # access to br-life only (see allowedTCPPorts below)
  services.redis.servers.default = {
    enable = true;
    bind = "0.0.0.0";
    port = 6379;
    save = [ [ 900 1 ] [ 300 10 ] [ 60 10000 ] ];
    settings = {
      dir = "/srv/databases/redis";
      # protected-mode blocks non-loopback connections when no password is set;
      # disable it since we rely on firewall for access control (same as postgres trust auth)
      protected-mode = "no";
    };
  };

  # allow containers on br-life to reach redis
  networking.firewall.interfaces.br-life.allowedTCPPorts = [ 6379 ];
}
