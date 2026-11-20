{
  flake.nixosModules.profiles-second-brain-hub =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.services-second-brain-default
        flakeModules.nixos.services-second-brain-clipper
      ];
    };
}
