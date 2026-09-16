{ inputs, ... }:
{
  flake.overlays.nur = inputs.nur.overlays.default;
}
