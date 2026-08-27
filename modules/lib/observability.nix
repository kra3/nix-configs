{ lib, ... }:
{
  # Alloy journal-source stanza forwarding one systemd unit's logs to Loki.
  # `id` (the alloy component instance label) defaults to `name` but must be
  # overridden when `name` contains characters River identifiers reject (e.g. "-").
  mkAlloyJournalSource =
    {
      name,
      hostName,
      id ? name,
      unit ? "${name}.service",
      role ? "host",
    }:
    ''
      loki.source.journal "${id}" {
        matches = "_SYSTEMD_UNIT=${unit}"
        labels = {
          job = "${name}",
          host = "${hostName}",
          role = "${role}",
        }
        forward_to = [loki.write.default.receiver]
      }
    '';
}
