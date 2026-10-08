---
name: ha-dashboards-automations
description: Use when building or changing Home Assistant dashboards, custom cards, automations, blueprints, packages or template sensors on sutala, or debugging HA, Frigate, Alarmo or Zigbee behaviour. Holds the workflow, UX principles, reuse rules, validation recipe and debugging playbook for this repo.
---

# Home Assistant on sutala

HA config is declarative in this repo; every change is verified before and after deploy, and every dashboard answers a question a person actually has. Repo-wide rules (worktree + PR, declarative fixes, no live manual steps) are in CLAUDE.md.

## Where things are
- Config: `modules/services/home-automation/home-assistant/ha-config/`: `configuration.yaml`, `lovelace.yaml` (card resources with `?v=N`), `dashboards/dashboard.yaml` + `dashboards/streamline_templates/`, `automations/`, `packages/`, `blueprints/automation/local/`, `custom_templates/*.jinja`, `www/*.js`.
- Container: `modules/containers/home-auto/home-assistant/container.nix` (mounts, secrets template, stop timeout, limits). Frigate: `modules/services/surveillance/nvr.nix`. Zigbee2MQTT declares no devices in the repo; Alarmo and the entity registry exist only in HA state.
- Endpoints, from sutala itself (no ssh): HA on port 8123, Prometheus on 9090, Loki on 3100; get the addresses from `docs/INVENTORY.md` and `modules/vars.nix`, never hardcode them (HA logs: `{systemd_unit="home-assistant.service"}`; Z2M and Frigate: text match on `{job=~".+"}`).
- API token: sops key `homeassistant.token`, read inside a script file with `nix develop -c sops -d --extract '["homeassistant.token"]' secrets/secrets.yaml`. Never print tokens or the Radarr/Sonarr/Seerr keys.
- Shell: zsh `noclobber` (use `>|`), `cat` is aliased to `bat`, no local `python3` or `yq` (use the HA container's Python); hooks block some compound `git push`/`git fetch` commands, so run git steps as small separate commands from a worktree.

## Workflow
- Present a short design and wait for an explicit yes before building; after approval, build without re-asking.
- Signed commits (`-S`) with the repo trailers. Bundle follow-ups into the same unmerged PR; check a PR is not merged before pushing to it (if it is, branch again off `origin/main`). If signing times out on pinentry, do not skip it: ask the user to run `! echo test | gpg --clearsign > /dev/null`, then retry.
- Confirm before any delete or overwrite.
- No code comments by default; reasoning goes in commit messages and PR bodies. PR text describes the final state.
- Evidence over assertion: query states, history and logs and cite them. State what is unverified ("not yet verified live"). Check the Z2M log before blaming hardware.
- When asked for the local path, give worktree, branch and `cd <worktree> && just switch sutala`. After a deploy, remind: restart HA if a package, secrets or template file changed; hard-refresh and reset the Companion app cache after card or dashboard changes.
- One-off scripts live in the scratchpad or `/tmp`, never the repo; put quote-heavy commands in a script file. Reports are short: result first, then only what the user must act on.

## Think beyond the request
- Find the cause behind the symptom and the real goal (e.g. lengthen the container stop timeout rather than only add a re-arm automation; light a room so the camera can see a person).
- Challenge a premise with evidence: read the integration's source and logs before assuming it handles a case.
- Check what a device control really does before exposing it.
- Name second-order effects before building: a fallback that fights the primary, a reset on every lights-off that wipes a mood after a film, detection that never turns off, defaults that make every room read "Cool".
- Offer 2-3 options with a recommendation when a real choice exists and say what is unknown; do not survey options you would not pursue.
- Prefer physically meaningful metrics (dew point, absolute humidity) over raw readings.
- Report adjacent breakage separately (a stale sensor, phantom contacts) without fixing it unasked.

## UX principles
- Start from the person, not the integration: who is in which room, what do they want to know or do, what should one glance show? A capability list is not a design.
- Every element earns its place: if a number tells nobody anything actionable, drop it (e.g. min-max on a count, a fixed 0-100 range, an unlabelled total).
- Show state and the next action: the active choice is highlighted, pending actions show pending (optimistic state with a timeout), and a visible "Auto" tile hands control back.
- One control per decision (a Downloading/Paused pill, a slider for a limit). Anything that can cut power or lock someone out is read-only on a dashboard; confirm only what is hard to undo (pausing automations, security), never routine toggles such as lights off.
- Name every control by what it does and say the effect in words: a hint line under each status value ("Lights follow the time of day"), state-specific where the state changes the meaning. Bare labels like "Automations: Running" are opaque. Hide an action that would do nothing right now (All lights off with no light on, Hand back with nothing in manual control). Ask what a plug or switch powers when the repo does not say, instead of guessing a name.
- A long catalogue (146 scene presets) is a picker with search and categories behind one button, not a long strip; keep the everyday choices one tap away.
- Reversible and honest: one tap back to normal, automation never silently fights a manual choice (decide and state when a manual state ends), unknown/unavailable is shown as such, "not reporting" is listed, rough sensors are marked "approx.".
- Consistent grammar across tabs, and improvements on one tab are applied to its siblings: terse labels, units on every value, icons as horizontal chips, used value with the percent inline (`423 GB 16 %`), growth (`+12 / 7d`) for counters, min-max only where a range means something, movies and TV kept split.
- Defaults are a starting point: expose thresholds as editable helpers and say what the defaults assume.
- Decide visuals by showing them (render icon or layout options) before committing.

## Adaptive layout (phone, tablet, desktop)
- Design every view for all three widths and write in the PR what each shows. Sections stack in file order, so file order is phone order: glance/status first, then the primary controls, then large visuals (floor plan, charts), then secondary content and settings. Desktop placement comes from the spans, not from reordering the file.
- The column count follows the viewport; `max_columns` is only a ceiling (a layout planned for 4 columns showed 3 on a narrower desktop and a span-1 section beside a span-2 one broke). Choose `max_columns` and `column_span`s that tile with no holes at every count from 1 to the max: with `max_columns: 2` use spans of 1 or 2, and give full-width strips the max span (clamped on narrow screens).
- Inside a section the grid has 12 columns per span and `grid_options.columns` counts out of that. Nested `grid`, chips, `conditional` and `tile` cards default to half width: set `grid_options: {columns: full}` on them. A fixed per-row count (`grid` with `columns: 2`) must still fit about 180 px on a phone; shorten names ("Wardrobe") rather than let them truncate.
- Custom cards reflow: `repeat(auto-fit, minmax(...))`, wrapping text, no fixed column count, no hover-only controls, touch targets about 44 px. An entities-card slider wraps its value at about 480 px; use `mushroom-number-card`.
- Check, do not assume: render custom cards in headless Chromium at about 390, 820 and 1280+ px, put the layout at each column count in the PR, and ask for a phone and a desktop screenshot after deploy (dashboards cannot be rendered offline). Truncation, holes or a stranded card in a screenshot is a defect: fix it in the same PR.

## Reuse and custom building
- Reuse first: blueprints (`room-presence-lighting`, `darkness-detection`), streamline templates, Jinja macros in `custom_templates/`, YAML anchors for lists used twice, existing cards. Parameterise instead of copying (template variable, blueprint input, macro argument). Extract a shared piece the second time something is copied.
- Prefer installed HACS cards and built-in tiles (mushroom, apexcharts-card, auto-entities, mini-media-player, advanced-camera-card, streamline-card, alarmo-card). Build a small custom card in `www/` only when no built-in gives the UX (active-tile highlight, read-only row, optimistic control): dependency-free, themed with HA CSS variables, tested in a headless harness.
- A new card is four edits: the file, a mount in `container.nix`, a resource in `lovelace.yaml` with `?v=N`, and the dashboard use. Put new mount/resource lines away from other open PRs' hunks.
- Extend an existing card with backward-compatible options rather than forking it. Custom cards in `www/`: `health-metric-card` (item `mode`, `range`, `chips`, `growth`, `deltaTone`, `secondary`, hero `unit`, `delta`, `popup.graphs`; flat histories collapse to one point, so growth reads `0 / 7d`), `status-row-card`, `download-control-card`, `security-plan-card` (`layer`), `security-status-card`, `home-hero-card`, `room-tile-card`, `popup-tile-card`, plus `scene-strip-card` once the Lights PR is merged. Read a card's source for its full options.

## Automation conventions
- Prefer a template sensor to an `input_boolean` plus hysteresis automation: templates recompute on startup, restored helpers do not.
- A state trigger's `for:` does not fire retroactively after a restart; add a startup branch when state must be reconciled.
- A fallback must not compete with the primary: act only if the primary result is absent.
- Template sensor entity ids derive from `name`, not `unique_id`. `input_number` with `initial` resets on every restart: seed defaults once behind a marker helper. `input_boolean` and `input_select` restore their last value.
- A quadlet container reading a sops template at a stable path needs a content-hash env var, or content-only edits never restart it.
- `darkness-detection` defaults (1000 lux) are unsafe for sensors that read above that in daylight. `room-presence-lighting` turns lights on from the person sensor only; motion just holds them on.
- Adaptive Lighting overwrites colours within about a minute unless `adaptive_lighting.set_manual_control` is set; hand back by clearing it and calling `adaptive_lighting.apply` with `turn_on_lights: false`.
- Scene Presets (HACS): `scene_presets.apply_preset` takes `preset_id` (UUID), `targets: {entity_id: [...]}`, `transition`; target individual bulbs, not a Hue group, so colours spread; preset images load without login from `/assets/scene_presets/<id>.jpeg`.

## Validation before a PR
- `nix fmt`, then CLAUDE.md's `check_config` recipe, adding read-only mounts for `custom_templates`, `scripts.yaml`, `lovelace.yaml` and `dashboards`. Known harmless output: two TV automations with an unknown device id, and `battery_notes` not found. Anything else is a real bug.
- `check_config` does not validate dashboards or service names. For a dashboard change, load old (`git show origin/main:...`) and new `dashboard.yaml` with `yaml.safe_load` in the HA container's Python (replace the `!include_dir_named` line first) and compare views to prove untouched ones are unchanged.
- Test Jinja macros against live states by posting a template with the macros inline to `POST /api/template`, and cross-check the maths by hand.
- Render custom cards in headless Chromium (`--allow-file-access-from-files`, injected `hass.states` and `callService`, `--screenshot`).
- Prove every changed automation fires: trigger it for real or check `last_triggered`, or say it was not verified.
- After deploy: `systemctl show home-assistant.service -p ActiveEnterTimestamp`, the entity or automation in `/api/states`, and `last_triggered` after a real trigger.

## Debugging playbook
1. States from `/api/states` (filter with `jq`); for an automation also `last_triggered`.
2. History with an explicit window and the Authorization header (no header returns `401: Unauthorized`, which breaks `jq`; the default window is 1 day). Check the `recorder:` excludes in `configuration.yaml` before trusting history: no history does not mean unchanged.
3. Loki around the timestamp: HA, Frigate, and Z2M (`MQTT publish: topic 'zigbee2mqtt/<name>'` shows exactly what a device last reported).
4. "Automation did nothing": list every condition and check each against live state.
5. Separate layers: card, HA entity, integration, device. A sensor that never reported a close is a device or radio problem, not a dashboard bug.
6. Confirm the fix is deployed before blaming a new cause: `origin/main`, service start time, entity set.
7. Restart state: HA's container stop timeout is 60 s so restore state is written on shutdown (Podman's 10 s default SIGKILLed it, losing the last write); alarm changes also call `homeassistant.save_persistent_states`. HA otherwise saves restore state every 15 minutes (a core constant).

## Domain facts
- Frigate: per-zone entities appear only after the integration reloads, and zone person sensors work only while `detect` is on. `detect` stays on only in `armed_away`; otherwise it wakes on camera motion and turns off after a quiet period, so someone who sits down while it is off stays invisible until motion fires. Tuning lives in `nvr.nix`.
- Alarmo restores through `RestoreEntity` and falls back to disarmed only with no saved state. `input_select.alarm_restore_mode` records only on an arm change.
- ZG-102ZM sensors are vibration-only: their `*_contact` entities never report (the "not reporting" chip on the Security banner).
- Only Profile, General, Default Dashboard persists the default dashboard on the server; the Dashboards-list "set default" is browser-local.
- Climate thresholds are `input_number.climate_*` with macros in `custom_templates/climate.jinja` (once the Climate PR is merged); Hue PIR rooms report no humidity.
