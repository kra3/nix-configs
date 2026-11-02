{
  flake.nixosModules.containers-home-auto-wyoming-piper-default =
    {
      config,
      flakeLib,
      flakeModules,
      ...
    }:
    let
      network = config.virtualisation.quadlet.networks.home-auto;
    in
    {
      imports = [ flakeModules.nixos.services-home-automation-wyoming-piper ];

      virtualisation.quadlet.containers.wyoming-piper = {
        containerConfig = {
          dns = [ "10.3.2.1" ];
          networks = [ "${network.ref}:ip=10.3.2.15" ];
          volumes = [
            "/var/cache/wyoming-piper:/data"
          ];
          # Sized from ~21h process-exporter peak + safety margin.
          memory = "896m";
          podmanArgs = [ "--cpus=1" ];
        };
      }
      // flakeLib.quadlet.mkNetworkDeps {
        networkServices = [ "home-auto-network.service" ];
      };

      systemd.tmpfiles.rules = [
        "d /var/cache/wyoming-piper 0750 root root - -"
      ];
    };
}
