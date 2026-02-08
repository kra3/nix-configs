{ lib, ... }:
{
  # Standard systemd sandboxing for services
  mkServiceSandbox = { readWritePaths ? [], capabilities ? [] }: {
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
    RestrictNamespaces = true;

    # Network
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];

    # Syscalls
    SystemCallFilter = [ "@system-service" "~@privileged" ];
    SystemCallArchitectures = "native";
  };

  # Container resource limits
  mkContainerLimits = { cpu ? "100%", memory, memoryHigh ? null }: {
    CPUQuota = cpu;
    MemoryMax = memory;
    MemoryHigh = if memoryHigh != null then memoryHigh else (
      # Default high = 80% of max
      let
        # Extract numeric value and unit
        memBytes = lib.toInt (lib.removeSuffix "G" (lib.removeSuffix "M" memory));
        unit = if lib.hasSuffix "G" memory then "G" else "M";
      in
        "${toString (memBytes * 80 / 100)}${unit}"
    );
    IOWeight = 100;
  };
}
