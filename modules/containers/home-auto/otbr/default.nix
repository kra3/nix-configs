{
  flake.nixosModules.containers-home-auto-otbr-default =
    {
      config,
      flakeLib,
      flakeModules,
      ...
    }:
    let
      network = config.virtualisation.quadlet.networks.home-auto;
      macvlan = config.virtualisation.quadlet.networks.home-auto-macvlan;
    in
    {
      imports = [ flakeModules.nixos.services-home-automation-otbr ];

      virtualisation.quadlet.containers.otbr = {
        containerConfig = {
          dns = [ "10.3.2.1" ];
          networks = [
            "${network.ref}:ip=10.3.2.11"
            "${macvlan.ref}:ip=192.168.1.34,mac=02:42:c0:a8:01:22"
          ];
          volumes = [
            "/srv/appdata/home-auto/otbr:/data"
          ];
          devices = [
            "/dev/thread:/dev/ttyUSB0"
            "/dev/net/tun:/dev/net/tun"
          ];
          addCapabilities = [
            "NET_ADMIN"
            "NET_RAW"
          ];
          # OTBR manages tun/iptables/ipset at runtime with file-capability binaries; keep exec privilege gain.
          noNewPrivileges = false;
          # Sized from ~21h process-exporter peak + safety margin.
          memory = "128m";
          podmanArgs = [ "--cpus=1" ];
        };
      }
      // flakeLib.quadlet.mkNetworkDeps {
        networkServices = [
          "home-auto-network.service"
          "home-auto-macvlan-network.service"
        ];
        extraAfter = [ "dev-thread.device" ];
        bindsTo = [ "dev-thread.device" ];
      };

      systemd.tmpfiles.rules = [
        "d /srv/appdata/home-auto/otbr 0750 root root - -"
      ];
    };
}
