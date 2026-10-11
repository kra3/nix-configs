{
  # Surasa can't build its own closure, so sutala builds `main` and switches it over SSH after its own upgrade window.
  flake.nixosModules.services-system-surasa-autodeploy =
    { config, pkgs, ... }:
    {
      systemd.services.surasa-autodeploy = {
        description = "Deploy main to surasa";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [
          config.system.build.nixos-rebuild
          config.nix.package
          pkgs.openssh
        ];
        environment.NIX_SSHOPTS = "-o BatchMode=yes";
        serviceConfig = {
          Type = "oneshot";
          User = "kra3";
          TimeoutStartSec = "2h";
          ExecStart = "${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch --flake github:kra3/nix-configs/main#surasa --refresh --target-host kra3@192.168.1.39 --build-host localhost --sudo";
        };
      };

      systemd.timers.surasa-autodeploy = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 08:00:00";
          Persistent = true;
        };
      };
    };
}
