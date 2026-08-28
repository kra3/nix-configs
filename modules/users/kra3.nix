{
  flake.nixosModules.users-kra3 =
  { config, pkgs, ... }:
  {
    sops.secrets."users.kra3.password".neededForUsers = true;
    sops.secrets."users.kra3.ssh_identity_key" = {
      group = "users";
      mode = "0640";
    };

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
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKmRf86XKYHd45ZmhhjyXFSgl88nH91dcSvRVNhVwn91 kra3@sutala github"
          ];
          hashedPasswordFile = config.sops.secrets."users.kra3.password".path;

          shell = pkgs.zsh;
        };
      };
    };

    home-manager.users.kra3 = {
      imports = [
        ../../hosts/sutala/home.nix
        ({ lib, ... }: {
          home.activation.installSshKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            $DRY_RUN_CMD mkdir -p ~/.ssh
            $DRY_RUN_CMD chmod 700 ~/.ssh
            $DRY_RUN_CMD install -m 600 \
              ${config.sops.secrets."users.kra3.ssh_identity_key".path} \
              ~/.ssh/id_ed25519
          '';
        })
      ];
    };

    system.activationScripts.kra3-sops-age-key = {
      deps = [ "setupSecrets" ];
      text = ''
        mkdir -p /home/kra3/.config/sops/age
        ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key \
          -i /home/kra3/.ssh/id_ed25519 \
          > /home/kra3/.config/sops/age/keys.txt
        chown kra3:users /home/kra3/.config/sops/age/keys.txt
        chmod 600 /home/kra3/.config/sops/age/keys.txt
      '';
    };

    nix.settings.trusted-users = [ "kra3" ];

    programs.zsh.enable = true;
  };
}
