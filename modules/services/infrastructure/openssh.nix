{
  flake.nixosModules.services-infrastructure-openssh =
    { config, ... }:
    {
      services.openssh = {
        enable = true;
        hostKeys = [
          {
            path = "/etc/ssh/ssh_host_ed25519_key";
            type = "ed25519";
          }
        ];
        openFirewall = false;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
          MaxAuthTries = 3;
          LoginGraceTime = 20;
          AllowUsers = [ "kra3" ];
        };
      };

      networking.firewall.interfaces.${config.vars.network.lanIf}.allowedTCPPorts = [ 22 ];
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
    };
}
