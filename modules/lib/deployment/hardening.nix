{ lib, ... }:
{
  flake.lib.deployment-hardening = {
    # Standard systemd sandboxing for services
    mkServiceSandbox =
      {
        readWritePaths ? [ ],
        capabilities ? [ ],
        allowNetworkNamespaces ? false,
        extraAddressFamilies ? [ ],
        # Extra knobs default to off so existing callers keep their current
        # serviceConfig unchanged; opt in per-service once reviewed.
        dynamicUser ? false,
        privateDevices ? false,
        protectKernelTunables ? false,
        protectKernelModules ? false,
        protectKernelLogs ? false,
        protectControlGroups ? false,
        protectClock ? false,
        protectHostname ? false,
        restrictRealtime ? false,
        memoryDenyWriteExecute ? false,
        restrictPrivilegedSyscalls ? false,
        memoryMax ? null,
        tasksMax ? null,
      }:
      {
        # Filesystem
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = readWritePaths;
        PrivateDevices = privateDevices;

        # Security
        NoNewPrivileges = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        LockPersonality = true;
        DynamicUser = dynamicUser;
        MemoryDenyWriteExecute = memoryDenyWriteExecute;
        RestrictRealtime = restrictRealtime;

        # Kernel/system surface
        ProtectKernelTunables = protectKernelTunables;
        ProtectKernelModules = protectKernelModules;
        ProtectKernelLogs = protectKernelLogs;
        ProtectControlGroups = protectControlGroups;
        ProtectClock = protectClock;
        ProtectHostname = protectHostname;

        # Capabilities
        CapabilityBoundingSet = capabilities;
        AmbientCapabilities = capabilities;

        # Namespaces
        RestrictNamespaces = if allowNetworkNamespaces then "~user ipc pid uts cgroup" else true;

        # Network
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ]
        ++ extraAddressFamilies;

        # Syscalls
        SystemCallFilter = [
          "@system-service"
        ]
        ++ lib.optionals restrictPrivilegedSyscalls [ "~@privileged" ];
        SystemCallArchitectures = "native";
      }
      // lib.optionalAttrs (memoryMax != null) { MemoryMax = memoryMax; }
      // lib.optionalAttrs (tasksMax != null) { TasksMax = tasksMax; };
  };
}
