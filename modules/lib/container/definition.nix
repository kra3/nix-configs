{ lib, ... }:
{
  flake.lib.container-definition = {
    # Standard systemd dependencies for containers
    mkContainerSystemdDeps = extraDeps: {
      requires = [
        "zfs-mount.service"
        "systemd-tmpfiles-resetup.service"
      ]
      ++ extraDeps;
      after = [
        "zfs-mount.service"
        "systemd-tmpfiles-resetup.service"
      ]
      ++ extraDeps;
    };

    # Standard container network configuration
    mkContainerNetwork = { hostAddress, localAddress }: {
      privateNetwork = true;
      inherit hostAddress localAddress;
    };
  };
}
