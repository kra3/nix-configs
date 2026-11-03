---
name: selfheal-logs
description: Show journald logs of the sutala self-heal agent - the current run live, the most recent run, or a specified past run. Use when asked what selfheal did, why a run failed, or to tail a run in progress.
---

# selfheal-logs

Each run is one invocation of `selfheal.service`. The journal holds one line per agent message (`say:`), tool call (`tool:`) and the final `result:`.

Current or most recent run:

```sh
journalctl -u selfheal.service --invocation=0 --no-pager
```

Follow a run in progress (stop with Ctrl-C; prefer a bounded read when running non-interactively):

```sh
journalctl -u selfheal.service -f
```

A past run: `--invocation=-1` is the run before the latest, `-2` the one before that, and so on. To pick by date, list invocations first:

```sh
journalctl -u selfheal.service -o json --output-fields=_SYSTEMD_INVOCATION_ID,MESSAGE --no-pager --since "7 days ago" \
  | jq -r 'select(.MESSAGE | test("^selfheal run ")) | "\(._SYSTEMD_INVOCATION_ID) \(.MESSAGE)"'
journalctl -u selfheal.service --invocation=<id> --no-pager
```

Full machine-readable transcripts are kept 30 days under `/var/lib/selfheal/runs/<run_id>/stream.jsonl` (root or selfheal only; use `sudo`).

Default to the most recent run unless the user names one. Summarise; quote error lines verbatim.
