{ lib, ... }:
{
  # Common custom types
  portType = lib.types.addCheck lib.types.port (p: p > 0 && p < 65536);

  # IP address type
  ipv4Type = lib.types.strMatching "^([0-9]{1,3}\\.){3}[0-9]{1,3}$";

  # Container name type
  containerNameType = lib.types.strMatching "^[a-zA-Z0-9_-]+$";
}
