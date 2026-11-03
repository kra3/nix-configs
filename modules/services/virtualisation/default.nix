{
  flake.nixosModules.services-virtualisation-default =
    {
      inputs,
      flakeModules,
      lib,
      ...
    }:
    {
      imports = [
        inputs.quadlet-nix.nixosModules.quadlet
        flakeModules.nixos.services-virtualisation-podman
      ];

      # Container baseline: no-new-privileges for every system-level quadlet container.
      # Opt out per container with `containerConfig.noNewPrivileges = false;` (plus a comment why).
      # Re-declaring the option merges this submodule into quadlet-nix's own container type.
      options.virtualisation.quadlet.containers = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            config.containerConfig.noNewPrivileges = lib.mkDefault true;
          }
        );
      };
    };
}
