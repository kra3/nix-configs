{ lib, ... }:
{
  flake.lib.login-autostart = {
    # Cross-platform "run this once at login" service: a launchd agent on
    # Darwin, a systemd user service on Linux. Returns a module, so it belongs
    # in `imports` — that lets the caller's own module evaluation resolve the
    # mkIf/mkMerge here alongside the rest of its config, instead of every
    # caller hand-rolling a mkMerge list at the call site.
    #
    # `script` must be idempotent shell (e.g. `foo || bar`): oneshot +
    # RunAtLoad only guarantees "ran once at login", not "never runs again on
    # unit restart" — and neither branch ever stops/unloads the unit itself,
    # so nothing here can tear down what it started.
    mkLoginAgent =
      { name, description, script }:
      { pkgs, ... }:
      lib.mkMerge [
        (lib.mkIf pkgs.stdenv.isDarwin {
          launchd.agents.${name} = {
            enable = true;
            config = {
              ProgramArguments = [
                "${pkgs.bash}/bin/bash"
                "-c"
                script
              ];
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
              ExecStart = "${pkgs.bash}/bin/bash -c '${script}'";
            };
          };
        })
      ];
  };
}
