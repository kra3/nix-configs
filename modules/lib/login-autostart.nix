{ lib, ... }:
{
  flake.lib.login-autostart = {
    # Cross-platform "run once at login" service: a launchd agent on Darwin, a
    # systemd user service on Linux. Returns a module — put it in `imports` so
    # the caller's own module evaluation resolves the mkIf/mkMerge below.
    #
    # `script` must be idempotent (e.g. `foo || bar`): RunAtLoad/oneshot only
    # guarantee it ran once at login, not that it never runs again, and
    # neither branch stops or unloads the unit on its own.
    mkLoginAgent =
      { name, description, script }:
      { pkgs, ... }:
      let
        # writeShellScript so both platforms exec the same file directly,
        # instead of quoting `script` into a `bash -c '<script>'` string.
        scriptPath = pkgs.writeShellScript name script;
      in
      lib.mkMerge [
        (lib.mkIf pkgs.stdenv.isDarwin {
          launchd.agents.${name} = {
            enable = true;
            config = {
              ProgramArguments = [ "${scriptPath}" ];
              RunAtLoad = true;
            };
          };
        })
        (lib.mkIf pkgs.stdenv.isLinux {
          systemd.user.services.${name} = {
            Unit.Description = description;
            Install.WantedBy = [ "default.target" ];
            Service = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${scriptPath}";
            };
          };
        })
      ];
  };
}
