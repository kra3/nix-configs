{
  flake.nixosModules.services-discovery-avahi =
    { config, lib, ... }:
    let
      lanIf = config.vars.network.lanIf;
    in
    {
      services.avahi = {
        enable = true;
        # mDNS relay between LAN and the media-play container.
        nssmdns4 = true;
        reflector = true;
        allowPointToPoint = true;
        allowInterfaces = [
          lanIf
          "ve-media-play"
        ];
      };

      networking.firewall.interfaces.${lanIf}.allowedUDPPorts = lib.mkAfter [ 5353 ];
      networking.firewall.interfaces.ve-media-play.allowedUDPPorts = lib.mkAfter [ 5353 ];
    };
}
