{
  flake.nixosModules.users-authelia =
  { ... }:
  {
    # Dedicated low-privilege account for Authelia's rootless podman
    # instance, mirroring modules/users/arcane.nix. No login method, no
    # SSH keys, no wheel/podman group membership — reachable only via
    # its own lingering systemd --user session, never interactively.
    users.groups.authelia = {
      gid = 2301;
    };

    users.users.authelia = {
      isNormalUser = true;
      uid = 2301;
      group = "authelia";
      description = "Rootless podman account for the Authelia identity provider";
      hashedPassword = null;
      linger = true;
      autoSubUidGidRange = true;
    };
  };
}
