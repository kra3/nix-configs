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
        prefetch = "yes";
        edns-buffer-size = 1232; # why ? 4096 is default, 1480 for fragmentation (seen as timeouts), 512 mtu issues
        harden-glue = "yes";
        harden-dnssec-stripped = "yes";
        use-caps-for-id = "yes";
        hide-identity = "yes";
        hide-version = "yes";
        minimal-responses = "yes";
        deny-any = "yes";
        harden-referral-path = "yes";
        harden-algo-downgrade = "yes";
        do-not-query-localhost = "yes";

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
            # "1.1.1.1@853#cloudflare-dns.com"
            # "1.1.1.1@853#security.cloudflare-dns.com"
            "1.1.1.1@853#family.cloudflare-dns.com"
            # "9.9.9.9@853#dns.quad9.net"
            "9.9.9.11@853#dns11.quad9.net"
          ];
        }
      ];
    };
  };

}
