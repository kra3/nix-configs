{
  flake.nixosModules.users-arcane =
    { ... }:
    {
      # Dedicated low-privilege account for Arcane's rootless podman instance
      # (modules/services/virtualisation/arcane.nix). No login method, no
      # SSH keys, no wheel/podman group membership — reachable only via its
      # own lingering systemd --user session, never interactively.
      users.groups.arcane = {
        gid = 2300;
      };

      users.users.arcane = {
        isNormalUser = true;
        uid = 2300;
        group = "arcane";
        description = "Rootless podman account for the Arcane container UI";
        hashedPassword = null;
        # Required for its systemd --user session (and rootless podman socket)
        # to start at boot without an interactive login.
        linger = true;
        autoSubUidGidRange = true;
      };
    };
}
