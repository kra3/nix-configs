{ lib, ... }:
{
  options.vars = {
    lanIf = lib.mkOption {
      type = lib.types.str;
      default = "enp2s0";
    };
    lanIp = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.10";
    };
  };
}
