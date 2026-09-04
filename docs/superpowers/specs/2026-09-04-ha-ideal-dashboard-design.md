# Home Assistant "Home (Ideal)" Dashboard Redesign

## Problem

`dashboards/dashboard_ideal.yaml` (served at `/dashboard-ideal/0`) is a flat inventory: 11 `type: area` tiles that render as inert icon+name (no live entity data, not interactive — HA's manually-authored `area` card doesn't behave like the auto-generated area-strategy tiles on HA's built-in dashboard), plus generic environment graphs and a security/media block duplicated from the existing "Home" dashboard. Verdict from live use: it adds no value over either the existing dashboard or HA's own default — same information, worse presentation.

A dashboard is worth keeping only if it does something neither of those does: show what's actionable *right now* rather than an inventory of everything, and adapt to *when*, *who's home*, and *who's looking at it*.

## Goals

- **Discoverability** — surface non-nominal state (alerts, pending overrides, active media) instead of a flat entity list.
- **Time-aware** — content shifts between day / evening / night.
- **Presence-aware** — content reflects who is physically home, not a static "everyone" view.
- **Location-aware** — zone-level presence (which named zone a tracked person is in) plus en-route/ETA when someone's neither home nor fully away.
- **Personal to the viewer** — the logged-in HA user shapes the view, cross-referenced with presence (a shared/wall-mounted device falls back to a presence-driven neutral view; a personal device shows that person's tailored view, adjusted by whether they're home/away).
- Runs **side-by-side** with the existing "Home" dashboard — this is additive, not a cutover — until it earns enough trust to replace it. It must be good enough to actually prefer, not just different.

## Non-Goals

- No changes to the existing "Home" dashboard, `lovelace.yaml`, or any automation.
- No new physical sensors or integrations — built entirely from entities that already exist (`person.*`, `schedule.sleep`, `sun.sun`, `alarm_control_panel.vasudha_secure`, area/occupancy sensors, `input_boolean.party_mode`, `input_boolean.automations_paused`).
- No custom backend/API — everything stays inside HA's own template-sensor + dashboard-YAML mechanisms, consistent with this repo's existing IaC pattern for automations/packages.

## Approaches Considered

1. **Template-sensor-driven single view with native `visibility:` conditions (chosen).** A small new HA package computes time/presence/alert state once as named entities; dashboard cards/sections reference them via HA's built-in per-card `visibility:` conditions. Single URL, live-reactive, state is reusable outside the dashboard.
2. **Static tabs per state, manually switched.** Zero template-sensor risk, but doesn't deliver on "aware" — the user still has to know which tab to check. Rejected: defeats the purpose.
3. **Fully self-contained in dashboard YAML** (e.g. `auto-entities` inline template filters for everything, no new sensors). Avoids new entities, but duplicates non-trivial Jinja (time-of-day logic) across many cards instead of one named state. Rejected as the primary mechanism, but its filtering strength is reused narrowly for the room row (see below) where a per-room predicate doesn't flatten cleanly into one sensor's state.

## Design

### Derived state (new package: `packages/dashboard_ideal_context.yaml`)

| Entity | States / behavior | Derivation |
|---|---|---|
| `sensor.dashboard_time_period` | `day`, `evening`, `night` | `day` = sun above horizon & `schedule.sleep` off; `evening` = sun below horizon & `schedule.sleep` off; `night` = `schedule.sleep` on. No separate "morning" state — sun+schedule don't split it cleanly and no actionable signal needs that granularity. |
| `sensor.dashboard_presence_state` | `away`, `home_arun`, `home_anjali`, `home_both` | From `person.arun_karunagath` + `person.anjalipc` state. |
| `sensor.dashboard_eta` | Set only when a tracked person is in a non-home/non-`not_home` named zone, or has live route attributes; otherwise empty/unset | `device_tracker`/`person` zone + attributes. Gives the en-route/ETA half of location-awareness. |
| `binary_sensor.dashboard_alert_security` | on/off | Any exit contact open while `alarm_control_panel.vasudha_secure` is `armed_away`, or alarm state is `triggered`. |
| `binary_sensor.dashboard_alert_device_health` | on/off | Any entity in a curated list is `unavailable`/`unknown`. |
| `binary_sensor.dashboard_alert_override_active` | on/off | `input_boolean.party_mode` on, `input_boolean.automations_paused` on, or a manual light-override flag. |

### Dashboard layout (`dashboard_ideal.yaml`)

1. **Top section — personalized + presence-swapped.** Three card variants, chosen by `visibility:` combining `condition: user` (which HA account is logged in on the viewing device) with `condition: state` on `sensor.dashboard_presence_state`:
   - Arun's view: shown when his account is logged in, content adjusted for home/away/one-of-two-home (his areas — office — surfaced first).
   - Anjali's view: same mechanism, her areas (kitchen/living) surfaced first.
   - Neutral/shared-device view: shown when neither personal login is active (e.g. a wall tablet); driven by `sensor.dashboard_presence_state` alone.

2. **Actionable-now feed.** Always visible. Built from the three alert booleans plus media/environment context (currently-playing media, temp/humidity/weather) — replaces the current static Environment/Security sections with something that only speaks when there's something non-nominal to report. This is the direct fix for "discoverability."

3. **Compact room row.** Replaces the flat 11-tile area grid. `auto-entities`-filtered (HACS card, already installed) to show only rooms that are occupied or have a device on/unavailable right now; each tile shows real live state (light on/off, temperature), not just an icon+name. HACS custom cards are open for use throughout this dashboard where they materially improve visual polish or function (not limited to `auto-entities`) — e.g. richer tile/mushroom-style cards for room and media state, provided they pull from entities that already exist.

4. **Kept as-is:** todo list, weather forecast, media controls for the two theater zones, badges row (persons, alarm, lock, waste, sun/moon/season) — none of this was the problem; the top section and room grid were.

### Testing / validation

Same discipline as the recent automations reorganization: `nix flake check` + `just build sutala` for structural wiring, then the containerized `check_config` script (per this repo's `CLAUDE.md`) against the live data dir before opening the PR — HA schema errors build and deploy cleanly but get silently disabled at startup, so this is the only real gate. Template sensors get the same scrutiny; bad Jinja in a package is exactly the same failure mode as a bad automation. Manual verification in-browser (both personal logins + a logged-out/neutral view, at least one state each for day/evening/night and away/home_arun/home_anjali/home_both) before calling it side-by-side-ready.

### Rollout

Deployed alongside the existing "Home" dashboard, unchanged. No cutover step in this spec — replacing "Home" is a future decision made only after the new dashboard has earned trust through real use.
