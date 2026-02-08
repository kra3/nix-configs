{ lib, config, ... }:
{
  deployment = {
    monitoring = import ./deployment/monitoring.nix { inherit lib config; };
    networking = import ./deployment/networking.nix { inherit lib; };
    storage = import ./deployment/storage.nix { inherit lib; };
    hardening = import ./deployment/hardening.nix { inherit lib; };
  };

  container = {
    definition = import ./container/definition.nix { inherit lib; };
    integration = import ./container/integration.nix { inherit lib; };
  };

  utils = {
    systemd = import ./utils/systemd.nix { inherit lib; };
    types = import ./utils/types.nix { inherit lib; };
  };
}
