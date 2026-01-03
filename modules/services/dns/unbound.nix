{ config, ... }:
let
  vars = config.vars;
in
{
  services.unbound = {
    enable = true;
    settings = {
      server = {
        interface = [ "127.0.0.1" ];
        access-control = [ "127.0.0.0/8 allow" ];
        port = 5335;
        do-daemonize = false;
        harden-glue = "yes";
        harden-dnssec-stripped = "yes";
        use-caps-for-id = "yes";
        prefetch = "yes";
        edns-buffer-size = 1232;

        local-zone = [
          ''"karunagath.in." redirect''
        ];
        local-data = [
          ''"karunagath.in. A ${vars.lanIp}"''
        ];
      };

      remote-control = {
        control-enable = true;
      };

      forward-zone = [
        {
          name = ".";
          forward-tls-upstream = true;
          forward-addr = [
            "1.1.1.1@853#cloudflare-dns.com"
            "9.9.9.9@853#dns.quad9.net"
          ];
        }
      ];
    };
  };
}
