{ lib, ... }:
{
  # Generate tmpfiles rules for directory creation
  mkDirs = dirs:
    lib.mapAttrsToList (path: { mode ? "0755", user ? "root", group ? "root" }:
      "d ${path} ${mode} ${user} ${group} - -"
    ) dirs;

  # Generate bind mount for container
  mkBindMount = { hostPath, containerPath ? hostPath, isReadOnly ? false }: {
    ${containerPath} = {
      inherit hostPath isReadOnly;
    };
  };

  # Standard app data mount pattern
  mkAppDataMount = { container, service, containerPath ? "/var/lib/${service}" }: {
    ${containerPath} = {
      hostPath = "/srv/appdata/${container}/${service}";
      isReadOnly = false;
    };
  };
}
