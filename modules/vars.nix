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
    nginxAllowCidrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "192.168.1.0/24"
        "100.64.0.0/10"
        "127.0.0.1"
      ];
    };
  };
}
