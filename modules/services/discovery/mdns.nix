{ config, lib, ... }:
let
  lanIf = config.vars.lanIf;
in
{
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    reflector = true;
    allowInterfaces = [
      lanIf
      "ve-media-play"
    ];
  };

  networking.firewall.interfaces.${lanIf}.allowedUDPPorts = lib.mkAfter [ 5353 ];
  networking.firewall.interfaces.ve-media-play.allowedUDPPorts = lib.mkAfter [ 5353 ];
}
