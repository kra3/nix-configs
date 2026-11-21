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
      // (
        let
          deps = flakeLib.quadlet.mkNetworkDeps {
            networkServices = [
              "home-auto-network.service"
              "home-auto-macvlan-network.service"
            ];
            extraAfter = [ "dev-thread.device" ];
            bindsTo = [ "dev-thread.device" ];
          };
        in
        deps
        // {
          # The image hard-codes the unauthenticated REST/web listeners to all interfaces; drop them on the LAN side (HA uses the bridge).
          # Leading "-": never fail the unit over this. "$$": systemd would otherwise expand $t.
          serviceConfig = deps.serviceConfig // {
            ExecStartPost = [
              "-/run/current-system/sw/bin/podman exec otbr sh -c 'for t in iptables ip6tables; do $$t -C INPUT -i eth1 -p tcp -m multiport --dports 8080,8081 -j DROP 2>/dev/null || $$t -I INPUT -i eth1 -p tcp -m multiport --dports 8080,8081 -j DROP; done'"
            ];
          };
        }
      );

      systemd.tmpfiles.rules = [
        "d /srv/appdata/home-auto/otbr 0750 root root - -"
      ];
    };
}
