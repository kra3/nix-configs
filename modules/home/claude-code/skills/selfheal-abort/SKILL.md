---
name: selfheal-abort
description: Stop the sutala self-heal agent. Two separate actions - `run` kills only the run in progress (tomorrow's run still fires), `schedule` disables the timer until re-enabled. Only when the user explicitly asks to abort, stop, or pause selfheal.
disable-model-invocation: true
argument-hint: run | schedule
---

# selfheal-abort

Argument: `$ARGUMENTS`

These are two distinct actions. Do exactly the one named in the argument. If the argument is missing or is anything other than `run` or `schedule`, do nothing and ask which one the user means, describing both. Never do both in one invocation and never infer one from the other.

## `run`: kill the run in progress only

```sh
sudo systemctl stop selfheal.service
systemctl list-timers selfheal.timer --no-pager
```

The schedule stays enabled; confirm by showing the next fire time.

## `schedule`: pause the whole schedule

```sh
sudo systemctl disable --now selfheal.timer
systemctl is-enabled selfheal.timer
```

This does not stop a run already in progress (use `run` for that). It lasts until `sudo systemctl enable --now selfheal.timer`, or the next `nixos-rebuild switch` / nightly auto-upgrade re-enables it, since the timer is declared with `wantedBy = timers.target`. For a pause that survives deploys, set `services.selfheal.enable = false` in `hosts/sutala/configuration.nix` through a PR.

Afterwards, report the resulting state with the `selfheal-status` commands.
