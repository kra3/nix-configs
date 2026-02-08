{ lib, ... }:
{
  options.vars = {
    network = {
      lanIf = lib.mkOption {
        type = lib.types.str;
        default = "enp2s0";
        description = "LAN network interface";
      };
      lanIp = lib.mkOption {
        type = lib.types.str;
        default = "192.168.1.10";
        description = "LAN IP address";
      };
      nginxAllowCidrs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "192.168.1.0/24"
          "100.64.0.0/10"
          "127.0.0.1"
        ];
        description = "CIDR blocks allowed for nginx access";
      };
    };
    acme = {
      email = lib.mkOption {
        type = lib.types.str;
        default = "the1.arun@gmail.com";
        description = "Email for ACME certificates";
      };
    };
  };
}
