{ lib, config, ... }:
{
  # Generate Alloy log source configuration
  # Supports both file-based and journald-based logging
  mkAlloyConfig = { name, paths ? [], journaldUnits ? [], extraLabels ? {} }:
    let
      fileSource = lib.optionalString (paths != []) ''
        loki.source.file "${name}_files" {
          targets = [
            ${lib.concatMapStringsSep "\n" (path: ''
              {
                __path__ = "${path}",
                job = "${name}",
                host = "''${config.networking.hostName}",
                role = "''${if config.boot.isContainer then "container" else "host"}",
                ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v:
                  "${k} = \"${v}\","
                ) extraLabels)}
              },
            '') paths}
          ]
          forward_to = [loki.write.default.receiver]
        }
      '';

      journaldSource = lib.optionalString (journaldUnits != []) ''
        loki.source.journal "${name}_journal" {
          matches = "${lib.concatMapStringsSep " " (unit: "_SYSTEMD_UNIT=${unit}") journaldUnits}"
          labels = {
            job = "${name}"
            host = "''${config.networking.hostName}"
            role = "''${if config.boot.isContainer then "container" else "host"}"
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k} = \"${v}\"") extraLabels)}
          }
          forward_to = [loki.write.default.receiver]
        }
      '';
    in
    fileSource + journaldSource;

  # Standard node-exporter setup
  mkNodeExporter = { port ? 9100 }: {
    services.prometheus.exporters.node = {
      enable = true;
      inherit port;
      enabledCollectors = [
        "systemd"      # CRITICAL: Required for container resource monitoring
        "processes"
        "tcpstat"
        "netdev"
        "netstat"
        "conntrack"
      ];
    };
  };

  # Service-specific exporter helper
  mkServiceExporter = { name, port, url, headers ? {} }: {
    services.prometheus.exporters.json = {
      enable = true;
      inherit port;
      url = url;
      # Additional config as needed
    };
  };
}
