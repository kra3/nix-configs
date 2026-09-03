{
  flake.nixosModules.containers-home-auto-wyoming-whisper-default = { config, flakeLib, flakeModules, ... }:
  let
    network = config.virtualisation.quadlet.networks.home-auto;
  in
  {
    imports = [ flakeModules.nixos.services-home-automation-wyoming-whisper ];

    virtualisation.quadlet.containers.wyoming-whisper = {
      containerConfig = {
        dns = [ "10.3.2.1" ];
        networks = [ "${network.ref}:ip=10.3.2.14" ];
        volumes = [
          "/srv/appdata/home-auto/wyoming-whisper:/data"
        ];
        # Sized from ~21h process-exporter peak + safety margin.
        memory = "512m";
        podmanArgs = [ "--cpus=1" ];
      };
    } // flakeLib.quadlet.mkNetworkDeps {
      networkServices = [ "home-auto-network.service" ];
    };

    systemd.tmpfiles.rules = [
      "d /srv/appdata/home-auto/wyoming-whisper 0750 root root - -"
    ];
  };
}
