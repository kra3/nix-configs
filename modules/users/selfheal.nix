{
  flake.nixosModules.users-selfheal = {
    users.groups.selfheal = {
      gid = 2302;
    };

    users.users.selfheal = {
      isSystemUser = true;
      uid = 2302;
      group = "selfheal";
      description = "Headless Claude Code self-heal agent";
      home = "/var/lib/selfheal";
      createHome = false;
      hashedPassword = null;
      extraGroups = [ "systemd-journal" ];
    };
  };
}
