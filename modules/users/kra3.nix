{ config, pkgs, ... }:
{
  sops.secrets."users.kra3.password".neededForUsers = true;

  users = {
    mutableUsers = false;

    users = {
      kra3 = {
        isNormalUser = true;
        createHome = true;
        description = "Arun Karunagath";
        extraGroups = [ "wheel" "podman" ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDpvhVfQVKDNfVyl4GJux/lfzjkm683EW4MAESX/JKQA sutala kra3"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOFHJcFS3rx+AoqmqhHSjMbWpe8KqcLTmX/xgcf7/lTn nixos-deploy"
        ];
        hashedPasswordFile = config.sops.secrets."users.kra3.password".path;

        # shell = pkgs.zsh;
      };
    };
  };

  home-manager.users.kra3 = {
    imports = [ ../home ];

    dotfiles = {
      desktop = false;
      work = false;
      githubUser = "kra3";
    };
  };

  nix.settings.trusted-users = [ "kra3" ];
}
