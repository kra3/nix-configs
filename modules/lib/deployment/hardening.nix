{ lib, ... }:
{
  # Standard systemd sandboxing for services
  mkServiceSandbox = { readWritePaths ? [], capabilities ? [], allowNetworkNamespaces ? false, extraAddressFamilies ? [] }: {
    # Filesystem
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    ReadWritePaths = readWritePaths;

    # Security
    NoNewPrivileges = true;
    RestrictSUIDSGID = true;
    RemoveIPC = true;
    LockPersonality = true;

    # Capabilities
    CapabilityBoundingSet = capabilities;
    AmbientCapabilities = capabilities;

    # Namespaces
    RestrictNamespaces = if allowNetworkNamespaces then "~user ipc pid uts cgroup" else true;

    # Network
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ] ++ extraAddressFamilies;

    # Syscalls
    SystemCallFilter = [ "@system-service" ];
    SystemCallArchitectures = "native";
  };
}
