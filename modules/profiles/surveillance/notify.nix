{
  flake.nixosModules.profiles-surveillance-notify =
    { config, flakeModules, ... }:
    {
      imports = [
        flakeModules.nixos.services-surveillance-camera-announce
      ];

      # camera-announce speaks via Piper TTS (PIPER_HOST), so voice must be present.
      assertions = [
        {
          assertion = config.virtualisation.quadlet.containers ? wyoming-piper;
          message = "profiles-surveillance-notify needs the Piper TTS container: import profiles-home-automation-voice.";
        }
      ];
    };
}
