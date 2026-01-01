{ config, pkgs, ... }:
{
  users = {
    mutableUsers = false;

    users = {
      kra3 = {
        isNormalUser = true;
        createHome = true;
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

  home-manager.users.kra3 = {
    home.stateVersion = "25.05";

    # Add user packages and services here.
    home.packages = with pkgs; [
      # Add user packages here.
    ];
  };

  nix.settings.trusted-users = [ "kra3" ];
}
