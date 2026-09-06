{
  flake.nixosModules.users-root =
    {
      config,
      lib,
      flakeModules,
      ...
    }:
    {
      sops.secrets."users.root.password".neededForUsers = true;

      users.users.root = {
        # No openssh.authorizedKeys: PermitRootLogin is "no" (services-infrastructure-openssh),
        # so root is only reachable via local console/sudo, never SSH.
        hashedPasswordFile = config.sops.secrets."users.root.password".path;
      };

      home-manager.users.root = {
        imports = [
          flakeModules.homeManager.home-shell-bash-default
          flakeModules.homeManager.home-profiles-core
        ];
        home.stateVersion = lib.mkDefault "25.11";
      };
    };
}
