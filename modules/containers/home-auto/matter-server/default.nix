{
  flake.nixosModules.containers-home-auto-matter-server-default = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.home-auto;
    macvlan = config.virtualisation.quadlet.networks.home-auto-macvlan;
  in
  {
    imports = [ flakeModules.nixos.services-home-automation-matter-server ];

    virtualisation.quadlet.containers.matter-server = {
      containerConfig = {
        dns = [ "10.3.2.1" ];
        networks = [
          "${network.ref}:ip=10.3.2.12"
          "${macvlan.ref}:ip=192.168.1.35,mac=02:42:c0:a8:01:23"
        ];
        volumes = [
          "/srv/appdata/home-auto/matter-server:/data"
        ];
        addCapabilities = [ "NET_ADMIN" ];
        # Sized from ~21h process-exporter peak + safety margin.
        memory = "384m";
        podmanArgs = [ "--cpus=1" ];
      };
    } // flakeLib.quadlet.mkNetworkDeps {
      networkServices = [ "home-auto-network.service" "home-auto-macvlan-network.service" ];
      extraAfter = [ "otbr.service" ];
    };

    systemd.tmpfiles.rules = [
      "d /srv/appdata/home-auto/matter-server 0750 root root - -"
    ];
  };
}
