---
name: selfheal-progress
description: Read the sutala self-heal agent's live progress file - current cluster N of M, phase, tool calls used against the per-cluster budget, and each cluster's outcome. Use when asked how far a selfheal run has got or what it found.
---

# selfheal-progress

The service keeps `/var/lib/selfheal/status.json` current while it works (world-readable). Read it:

```sh
selfheal-status show
```

(`selfheal-status` is on PATH on sutala; `jq . /var/lib/selfheal/status.json` is equivalent.)

Schema:

| Field | Meaning |
|---|---|
| `run_id` | UTC start stamp, also the directory under `/var/lib/selfheal/runs/` |
| `mode` | `dry-run` or `live` |
| `phase` | `starting`, `diagnose`, `cluster`, `rediagnose`, `classify`, `act`, `digest`, then `publish` and `done` (set by `selfheal-publish.service`) |
| `cluster.index` / `cluster.total` | cluster N of M being worked (0 before clustering) |
| `cluster.tool_calls` | tool calls spent on the current cluster |
| `tool_calls.total` / `tool_calls.budget_per_cluster` | whole-run count and the escalation budget |
| `clusters[]` | `index`, `title`, `outcome` (`in-progress`, `no-issue`, `would-fix`, `would-escalate`, `fix-committed`, `pr-opened`, `escalated`, `skipped`), `detail`, `pr` |
| `started_at`, `updated_at`, `finished_at`, `result` | timestamps; `result` is the run's end state |

Summarise as: `cluster N/M <title> - <phase>, <cluster.tool_calls>/<budget> tool calls`, then one line per finished cluster with its outcome. If `updated_at` is old and the service is inactive, the run is over; say so and show `result`.

The digest that was posted to Telegram is `/var/lib/selfheal/runs/<run_id>/digest.txt` (readable by root and the selfheal user).
