{ config, inputs, lib, pkgs, ... }:
let
  lanIf = config.vars.lanIf;
  mediaPlayHostIp = config.containers.media-play.hostAddress or "10.0.50.5";
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
      mediaPlayHostIp
    ];
    extraConfig = "--noMDNS --noSonosDiscovery";
  };

  systemd.services.multicast-relay = {
    after = [
      "container@media-play.service"
      "network-online.target"
    ];
    wants = [
      "container@media-play.service"
      "network-online.target"
    ];
  };

  networking.firewall.interfaces.${lanIf}.allowedUDPPorts = lib.mkAfter [ 1900 ];
  networking.firewall.interfaces.ve-media-play.allowedUDPPorts = lib.mkAfter [ 1900 ];
}
