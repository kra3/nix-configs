{ lib }:
{
  deployment = {
    hardening = import ./deployment/hardening.nix { inherit lib; };
  };

  container = {
    definition = import ./container/definition.nix { inherit lib; };
  };

  quadlet = import ./quadlet.nix { inherit lib; };
  nginx = import ./nginx.nix { inherit lib; };
  observability = import ./observability.nix { inherit lib; };
}
