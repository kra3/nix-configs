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
        };
      };

      networking.firewall.interfaces.${config.vars.network.lanIf}.allowedTCPPorts = [ 22 ];
    };
}
