{
  lib,
  inputs,
  flakeModules,
  flakeLib,
  ...
}:
{
  imports = [
    flakeModules.darwin.nixpkgs-overlays-darwin
  ];

  # nix-darwin requires this for managed shells.
  programs.zsh.enable = true;

  # Determinate owns nix on this machine; nix-darwin must not also manage it.
  nix.enable = false;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs flakeModules flakeLib; };
    sharedModules = [ inputs.catppuccin.homeModules.catppuccin ];
  };

  home-manager.users.akarunagath = {
    imports = [
      flakeModules.homeManager.home-profiles-core
      flakeModules.homeManager.home-profiles-dev
      flakeModules.homeManager.home-profiles-shell
      flakeModules.homeManager.home-shell-default
      flakeModules.homeManager.home-work
      flakeModules.homeManager.home-ghostty
      flakeModules.homeManager.home-aerospace
      flakeModules.homeManager.home-jankyborders
      flakeModules.homeManager.home-sketchybar
      flakeModules.homeManager.home-wallpaper-darwin
    ];

    home.username = "akarunagath";
    home.homeDirectory = lib.mkForce "/Users/akarunagath";

    catppuccin.enable = true;
    catppuccin.flavor = "mocha";
    catppuccin.accent = "blue";

    home.stateVersion = lib.mkDefault "25.11";
  };

  system.primaryUser = "akarunagath";

  security.pam.services.sudo_local.touchIdAuth = true;

  system.defaults = {
    dock = {
      autohide = true;
      mru-spaces = false;
      show-recents = false;
      minimize-to-application = true;
    };
    spaces.spans-displays = true;
    trackpad = {
      Clicking = true;
      Dragging = true;
    };
    finder = {
      CreateDesktop = false;
      FXPreferredViewStyle = "Nlsv";
      ShowPathbar = true;
      ShowStatusBar = true;
      FXEnableExtensionChangeWarning = false;
      FXDefaultSearchScope = "SCcf";
    };
    screencapture.location = "~/Desktop";
    loginwindow.GuestEnabled = false;
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      AppleShowAllExtensions = true;
      _HIHideMenuBar = true;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      ApplePressAndHoldEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticCapitalizationEnabled = false;
      NSWindowShouldDragOnGesture = true;
    };
  };

  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
  };

  system.stateVersion = 6;
}
