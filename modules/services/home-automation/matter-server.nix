{
  flake.nixosModules.services-home-automation-matter-server =
    { config, flakeLib, ... }:
    {
      virtualisation.quadlet.containers.matter-server = {
        containerConfig = {
          image = "ghcr.io/home-assistant-libs/python-matter-server:8.1.0";
          publishPorts = [ "127.0.0.1:5580:5580" ];
          # Image default cmd plus --listen-address: the ws API is unauthenticated, keep it off the macvlan LAN address.
          exec = "--storage-path /data --paa-root-cert-dir /data/credentials --listen-address 10.3.2.12";
          logDriver = "journald";
          environments = {
            TZ = "Europe/Stockholm";
          };
        };
      };

      environment.etc."alloy/matter-server.alloy".text = flakeLib.observability.mkAlloyJournalSource {
        name = "matter-server";
        id = "matter_server";
        hostName = config.networking.hostName;
      };
    };
}
