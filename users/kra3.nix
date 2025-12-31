{ config, ... }:
{
  users = {
    mutableUsers = false;

    users = {
      root = {
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMY4lTahzgn3hOIq3edXBPzg2XdJlcYUBIdWm0BD2HkP sutala root"
        ];
        hashedPasswordFile = config.sops.secrets."root-password".path;
      };

      kra3 = {
        isNormalUser = true;
        description = "Arun Karunagath";
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDpvhVfQVKDNfVyl4GJux/lfzjkm683EW4MAESX/JKQA sutala kra3"
        ];
        hashedPasswordFile = config.sops.secrets."kra3-password".path;

        # shell = pkgs.zsh;
      };
    };
  };
}
