{
  flake.nixosModules.containers-media-mgmt-rreading-glasses =
    {
      config,
      flakeLib,
      flakeModules,
      ...
    }:
    let
      network = config.virtualisation.quadlet.networks.media-mgmt;
      ip = config.vars.network.podmanAddresses.rreading-glasses;
    in
    {
      imports = [ flakeModules.nixos.services-media-acquisition-rreading-glasses ];

      sops.secrets."media.rreading-glasses.hardcover_auth" = { };

      sops.templates."media.rreading-glasses.env" = {
        owner = "root";
        group = "media";
        mode = "0440";
        content = ''
          HARDCOVER_AUTH=Bearer ${config.sops.placeholder."media.rreading-glasses.hardcover_auth"}
          POSTGRES_HOST=host.containers.internal
          POSTGRES_DATABASE=rreading_glasses
          POSTGRES_USER=rreading_glasses
          POSTGRES_PASSWORD=${config.sops.placeholder."db.rreading_glasses_password"}
        '';
      };

      virtualisation.quadlet.containers.rreading-glasses = {
        containerConfig = {
          networks = [ "${network.ref}:ip=${ip}" ];
          memory = "256m";
          podmanArgs = [ "--cpus=1" ];
        };
      }
      // flakeLib.quadlet.mkNetworkDeps {
        networkServices = [ "media-mgmt-network.service" ];
        extraAfter = [ "postgresql-set-passwords.service" ];
        extraRequires = [ "postgresql-set-passwords.service" ];
      };
    };
}
