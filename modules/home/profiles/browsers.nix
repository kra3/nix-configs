{
  flake.homeManagerModules.home-profiles-browsers =
    { pkgs, domain, ... }:
    {
      programs.librewolf = {
        enable = true;
        profiles.default = {
          isDefault = true;
          # RFP normalizes content prefers-color-scheme to light for anti-fingerprinting;
          # override so sites follow the system theme like they do in Chromium.
          settings."layout.css.prefers-color-scheme.content-override" = 2;
          settings."browser.startup.homepage" = "https://home.${domain}";
          bookmarks.force = true;
          bookmarks.settings = [
            {
              name = "Toolbar";
              toolbar = true;
              bookmarks = [ ];
            }
          ];
          # HM only symlinks these xpis, so sideloaded add-ons start disabled in
          # about:addons; bitwarden is force-enabled via policies below.
          extensions.packages =
            (with pkgs.nur.repos.rycee.firefox-addons; [
              ublock-origin
              bitwarden
              privacy-badger
              facebook-container
              dashlane
              sponsorblock
              multi-account-containers
              vimium
            ])
            ++ [
              # Not packaged in NUR; built directly from AMO since Nix pins the version anyway.
              (pkgs.nur.repos.rycee.firefox-addons.buildFirefoxXpiAddon {
                pname = "sink-it-for-reddit";
                version = "8.9.0";
                addonId = "{09acf9ff-55d4-4366-a1a9-c9b3c8877c09}";
                url = "https://addons.mozilla.org/firefox/downloads/file/5006503/sink_it_for_reddit-8.9.0.xpi";
                sha256 = "sha256-JiZDnxJRbgyTI111GiIfGDzFl5Yk4i6mHoBsEshCofs=";
                meta = with pkgs.lib; {
                  description = "Sink It for Reddit";
                  homepage = "https://addons.mozilla.org/en-US/firefox/addon/sink-it-for-reddit/";
                  license = licenses.unfree;
                  mozPermissions = [ ];
                  platforms = platforms.all;
                };
              })
            ];
        };
      };
      # Force-enable Bitwarden from the Nix-pinned xpi above (not AMO), and point it
      # at the self-hosted Vaultwarden so the login screen is pre-set to it.
      programs.librewolf.policies =
        let
          bitwarden = pkgs.nur.repos.rycee.firefox-addons.bitwarden;
        in
        {
          ExtensionSettings.${bitwarden.addonId} = {
            installation_mode = "force_installed";
            install_url = "file://${bitwarden}/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/${bitwarden.addonId}.xpi";
          };
          "3rdparty".Extensions.${bitwarden.addonId}.environment.base = "https://vault.${domain}";
        };
      catppuccin.librewolf.force = true;

      programs.chromium = {
        enable = true;
        package = pkgs.ungoogled-chromium;
        # Bitwarden (Chrome Web Store id). HM installs it via Chromium's
        # External Extensions mechanism using the Web Store update URL.
        extensions = [
          { id = "nngceckbapebfimnlniiiahkandclblb"; }
        ];
      };

      # xdg-open has no default browser without this, so apps that shell out to it
      # (e.g. Picard's "Lookup in Browser") silently do nothing.
      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "text/html" = "librewolf.desktop";
          "x-scheme-handler/http" = "librewolf.desktop";
          "x-scheme-handler/https" = "librewolf.desktop";
          "x-scheme-handler/about" = "librewolf.desktop";
          "x-scheme-handler/unknown" = "librewolf.desktop";
        };
      };
    };
}
