{ lib, ... }:
{
  # Generate systemd service options
  mkService = { description, after ? [], requires ? [], serviceConfig }: {
    inherit description after requires serviceConfig;
    wantedBy = [ "multi-user.target" ];
  };

  # Helper for oneshot services
  mkOneshotService = { description, script, after ? [] }: {
    inherit description after;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = script;
    };
    wantedBy = [ "multi-user.target" ];
  };
}
