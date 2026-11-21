{
  flake.nixosModules.profiles-home-automation-voice =
    { flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.containers-home-auto-wyoming-whisper-default
        flakeModules.nixos.containers-home-auto-wyoming-piper-default
      ];
    };
}
