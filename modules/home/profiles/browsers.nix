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
          # bitwarden is installed but left disabled in about:addons on first launch
          # (no declarative "installed but off" state; HM just symlinks the xpi).
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
      catppuccin.librewolf.force = true;

      programs.chromium = {
        enable = true;
        package = pkgs.ungoogled-chromium;
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
