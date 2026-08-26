{ lib }:
{
  deployment = {
    hardening = import ./deployment/hardening.nix { inherit lib; };
  };

  container = {
    definition = import ./container/definition.nix { inherit lib; };
  };
}
