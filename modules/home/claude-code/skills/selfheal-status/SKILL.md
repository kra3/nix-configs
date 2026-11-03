---
name: selfheal-status
description: Show the sutala self-heal agent's schedule and service state - whether selfheal.timer is enabled, the last run's result and when the next run fires. Use when asked whether selfheal is running, enabled, paused, or when it last/next ran.
---

# selfheal-status

Run on sutala (the service only exists there):

```sh
systemctl list-timers selfheal.timer --all --no-pager
systemctl status selfheal.timer selfheal.service --no-pager --lines=0
systemctl show selfheal.service -p ActiveState,Result,ExecMainStatus,ExecMainStartTimestamp,ExecMainExitTimestamp --no-pager
jq '{run_id, mode, phase, started_at, finished_at, result}' /var/lib/selfheal/status.json
```

Report, in a few lines:
- timer: enabled or disabled, next fire time, last fire time
- service: active (a run is in progress) or inactive, last result and exit status
- last run: run id, mode (`dry-run` or `live`), result

`mode` comes from `services.selfheal.dryRun` / `dryRunDays` in `modules/services/selfheal.nix`; live mode needs `dryRun = false` and at least `dryRunDays` since the first run.

For progress inside a running run use `selfheal-progress`; for logs use `selfheal-logs`.
