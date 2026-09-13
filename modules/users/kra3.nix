{
  flake.nixosModules.users-kra3 =
    { config, pkgs, ... }:
    {
      sops.secrets."users.kra3.password".neededForUsers = true;
      sops.secrets."users.kra3.ssh_identity_key" = {
        group = "users";
        mode = "0640";
      };

      sops.secrets."music.acoustid_api_key" = {
        owner = "kra3";
      };
      sops.secrets."music.spotify_client_id" = {
        owner = "kra3";
      };
      sops.secrets."music.spotify_client_secret" = {
        owner = "kra3";
      };
      sops.secrets."music.deepseek_api_key" = {
        owner = "kra3";
      };
      sops.secrets."music.fanarttv_api_key" = {
        owner = "kra3";
      };

      # beets' own config.yaml (tracked in Nix) never holds this key; `beet` is
      # aliased (see home-music-beets) to overlay this file via `--config` at invocation time.
      sops.templates."music/beets-secrets.yaml" = {
        owner = "kra3";
        mode = "0400";
        content = ''
          acoustid:
            apikey: ${config.sops.placeholder."music.acoustid_api_key"}
          spotify:
            client_id: ${config.sops.placeholder."music.spotify_client_id"}
            client_secret: ${config.sops.placeholder."music.spotify_client_secret"}
          aisauce:
            providers:
              - id: deepseek
                model: deepseek-flash
                api_base_url: https://api.deepseek.com
                api_key: ${config.sops.placeholder."music.deepseek_api_key"}
          fetchart:
            fanarttv_key: ${config.sops.placeholder."music.fanarttv_api_key"}
        '';
      };

      # Separate from beets-secrets.yaml (not just an aisauce.mode overlay) because beets'
      # --config flag doesn't stack: only the last one wins, so a partial overlay silently
      # drops the providers list. This template duplicates the full secrets so the
      # beet-cleanup alias's single --config is self-contained.
      sops.templates."music/beets-cleanup-secrets.yaml" = {
        owner = "kra3";
        mode = "0400";
        content = ''
          acoustid:
            apikey: ${config.sops.placeholder."music.acoustid_api_key"}
          spotify:
            client_id: ${config.sops.placeholder."music.spotify_client_id"}
            client_secret: ${config.sops.placeholder."music.spotify_client_secret"}
          aisauce:
            mode: metadata_cleanup
            providers:
              - id: deepseek
                model: deepseek-flash
                api_base_url: https://api.deepseek.com
                api_key: ${config.sops.placeholder."music.deepseek_api_key"}
          fetchart:
            fanarttv_key: ${config.sops.placeholder."music.fanarttv_api_key"}
        '';
      };

      sops.templates."music/api-keys.env" = {
        owner = "kra3";
        mode = "0400";
        content = ''
          ACOUSTID_API_KEY=${config.sops.placeholder."music.acoustid_api_key"}
          SPOTIFY_CLIENT_ID=${config.sops.placeholder."music.spotify_client_id"}
          SPOTIFY_CLIENT_SECRET=${config.sops.placeholder."music.spotify_client_secret"}
        '';
      };

      users = {
        mutableUsers = false;

        users = {
          kra3 = {
            isNormalUser = true;
            createHome = true;
            description = "Arun Karunagath";
            extraGroups = [
              "wheel"
              "podman"
              "media"
            ];
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDpvhVfQVKDNfVyl4GJux/lfzjkm683EW4MAESX/JKQA sutala kra3"
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOFHJcFS3rx+AoqmqhHSjMbWpe8KqcLTmX/xgcf7/lTn nixos-deploy"
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKmRf86XKYHd45ZmhhjyXFSgl88nH91dcSvRVNhVwn91 kra3@sutala github"
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBsFDX6538hbMO6C/JtV3fJQPu3bY/LXSwnwl7OVxrqI kra3@surasa recovery"
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
