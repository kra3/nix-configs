{ config, inputs, lib, pkgs, ... }:
let
  lanIf = config.vars.lanIf;
  ijohanne = import inputs.ijohanne-nur { inherit pkgs; };
in
{
  imports = [
    ijohanne.modules.multicast-relay
  ];

  nixpkgs.overlays = [
    (final: prev: {
      multicast-relay = (import inputs.ijohanne-nur { pkgs = final; }).multicast-relay;
    })
  ];

  services.multicast-relay = {
    enable = true;
    interfaces = [
      lanIf
      "ve-media-play"
    ];
    extraConfig = "--noMDNS --noSonosDiscovery";
  };

  networking.firewall.interfaces.${lanIf}.allowedUDPPorts = lib.mkAfter [ 1900 ];
  networking.firewall.interfaces.ve-media-play.allowedUDPPorts = lib.mkAfter [ 1900 ];
}
