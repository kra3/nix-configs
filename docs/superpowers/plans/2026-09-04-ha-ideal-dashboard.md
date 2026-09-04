# HA "Home (Ideal)" Dashboard Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat, data-less area-tile grid in `dashboard_ideal.yaml` with a dashboard that surfaces actionable state (not an inventory), adapts to time/presence, and is personalized to the logged-in viewer — while running side-by-side with the existing "Home" dashboard.

**Architecture:** A new HA package (`packages/dashboard_ideal_context.yaml`) computes derived state once as template sensors (time period, presence, ETA, three alert booleans). `dashboard_ideal.yaml` consumes that state entirely through HA's native per-card `visibility:` conditions — no custom backend, no new HACS dependency (this HA instance has `mushroom`, `alarmo-card`, `advanced-camera-card`, `webrtc-camera` installed; `auto-entities` is **not** installed, confirmed via `HEAD /hacsfiles/lovelace-auto-entities/auto-entities.js` → 404, so the room row uses built-in `tile`/`mushroom-template-card` cards with per-card visibility instead).

**Tech Stack:** Home Assistant YAML packages (`template:` platform), Lovelace `sections` dashboard YAML, `mushroom-template-card` (already-installed HACS card), Nix/Podman quadlet (this repo's existing HA deployment path — no changes needed there, packages/dashboards are already whole-directory bind mounts).

**Spec:** `docs/superpowers/specs/2026-09-04-ha-ideal-dashboard-design.md`

## Global Constraints

- No changes to the existing "Home" dashboard, `lovelace.yaml`, or any automation file.
- No new HACS resources — build only with entities/cards confirmed to already exist in this deployment (see verified-facts table below).
- Every HA config change must pass the containerized `check_config` script (per this repo's root `CLAUDE.md`) before the PR is opened — schema errors build and deploy cleanly but silently disable at HA startup.
- `nix flake check` and `just build sutala` must stay green after every task.

### Verified facts (gathered live against `ha.karunagath.in`, 2026-09-04)

| Fact | Value |
|---|---|
| Arun's HA user id | `a1d4401b8b714ebb83f07c5316ab399c` |
| Anjali's HA user id | `6edcc5a09c3144d684077ee362e7394a` |
| Zones defined | `zone.home`, `zone.work`, `zone.oxie_station` |
| Person state semantics | entity state = zone friendly name when inside a zone (e.g. `home`, `Work`), else `not_home` |
| Existing reusable alert entity | `binary_sensor.house_exits_open_status` (packages/environment.yaml) — any exit open |
| Rooms with a composite occupancy sensor | `binary_sensor.hallway_occupancy_status`, `binary_sensor.living_room_occupancy_status`, `binary_sensor.dining_room_occupancy_status`, `binary_sensor.kitchen_occupancy_status`, `binary_sensor.bed_room_occupancy_status`, `binary_sensor.laundry_room_occupancy_status`, `binary_sensor.bathroom_occupancy_status` |
| Rooms with no composite occupancy sensor | `front`, `kitchen_dining_room`, `office`, `toilet` — fall back to a representative light entity, or always-show if neither exists |
| Representative light per room | kitchen→`light.kitchen_light_1`, kitchen_dining_room→`light.kitchen_dining_light_1`, dining_room→`light.dining_room_light_1`, living_room→`light.tv_backlight`, hall→`light.hall`, bedroom→`light.bedroom_wardrobe_light_1`, office→`light.office_room_light`; front/bathroom/toilet/laundry have none |
| Media players (dashboard's own) | `media_player.lg_webos_tv_oled77c35la`, `media_player.home_theater`, `media_player.home_theater_2` |
| Existing avg sensors (reused) | `sensor.average_temperature`, `sensor.average_humidity`, `sensor.average_illuminance` |
| HACS resources registered | `lovelace-mushroom`, `webrtc-camera`, `advanced-camera-card`, `alarmo-card` only |
| `packages/` is loaded via | `configuration.yaml`: `packages: !include_dir_named packages` — any new file dropped in `packages/` is picked up automatically, no `configuration.yaml` or `container.nix` edit needed (the directory is already bind-mounted whole) |

---

## Task 1: Derived-state package — time, presence, ETA

**Files:**
- Create: `modules/services/home-automation/home-assistant/ha-config/packages/dashboard_ideal_context.yaml`

**Interfaces:**
- Produces: `sensor.dashboard_time_period` (states: `day`/`evening`/`night`), `sensor.dashboard_presence_state` (states: `away`/`home_arun`/`home_anjali`/`home_both`), `sensor.dashboard_eta` (free-text state, `none` when nobody is en route)

- [ ] **Step 1: Write the package file**

```yaml
# Derived state for the "Home (Ideal)" dashboard (dashboards/dashboard_ideal.yaml).
# Computed once here so dashboard cards can reference plain entity state via
# native `visibility:` conditions instead of duplicating Jinja per-card.
template:
  - sensor:
      - name: "Dashboard Time Period"
        unique_id: dashboard_time_period
        state: >-
          {% if is_state('schedule.sleep', 'on') %}
            night
          {% elif is_state('sun.sun', 'above_horizon') %}
            day
          {% else %}
            evening
          {% endif %}

      - name: "Dashboard Presence State"
        unique_id: dashboard_presence_state
        state: >-
          {% set arun_home = is_state('person.arun_karunagath', 'home') %}
          {% set anjali_home = is_state('person.anjalipc', 'home') %}
          {% if arun_home and anjali_home %}
            home_both
          {% elif arun_home %}
            home_arun
          {% elif anjali_home %}
            home_anjali
          {% else %}
            away
          {% endif %}

      - name: "Dashboard ETA"
        unique_id: dashboard_eta
        state: >-
          {% set people = {'person.arun_karunagath': 'Arun', 'person.anjalipc': 'Anjali'} %}
          {% set ns = namespace(parts=[]) %}
          {% for entity_id, label in people.items() %}
            {% set st = states(entity_id) %}
            {% if st not in ['home', 'not_home', 'unknown', 'unavailable'] %}
              {% set ns.parts = ns.parts + [label ~ ' near ' ~ st] %}
            {% endif %}
          {% endfor %}
          {{ ns.parts | join(', ') if ns.parts else 'none' }}
```

- [ ] **Step 2: Validate YAML structurally**

Run: `nix develop -c just build sutala`
Expected: build succeeds (this only confirms the file is tracked by git and wires into the Nix/podman mount correctly — it does NOT validate HA's own schema, see Step 3).

- [ ] **Step 3: Validate against HA's schema**

Run the containerized `check_config` script from this repo's root `CLAUDE.md` (mount the full set of read-only paths it lists, including the now-existing `packages/` directory) against the live `sutala` data dir. Ask the user to run this if `sudo`/SSH access isn't available in-session.
Expected: no "could not be validated and has been disabled" or "Failed config" line. If `sensor.dashboard_time_period` etc. appear in the printed entity list (or no error is raised for the `template:` block), the package parsed correctly.

- [ ] **Step 4: Commit**

```bash
git add modules/services/home-automation/home-assistant/ha-config/packages/dashboard_ideal_context.yaml
git commit -m "$(cat <<'EOF'
Add derived time/presence/ETA sensors for ideal dashboard

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WticZrVkywjzmnsf7inVyF
EOF
)"
```

---

## Task 2: Derived-state package — alert booleans

**Files:**
- Modify: `modules/services/home-automation/home-assistant/ha-config/packages/dashboard_ideal_context.yaml`

**Interfaces:**
- Consumes: `binary_sensor.house_exits_open_status`, `alarm_control_panel.vasudha_secure`, `input_boolean.party_mode`, `input_boolean.automations_paused` (all pre-existing)
- Produces: `binary_sensor.dashboard_alert_security`, `binary_sensor.dashboard_alert_device_health`, `binary_sensor.dashboard_alert_override_active` (all on/off)

- [ ] **Step 1: Append the binary_sensor block to the same `template:` key**

```yaml
  - binary_sensor:
      - name: "Dashboard Alert: Security"
        unique_id: dashboard_alert_security
        device_class: safety
        state: >-
          {{ is_state('alarm_control_panel.vasudha_secure', 'triggered')
             or (is_state('alarm_control_panel.vasudha_secure', 'armed_away')
                 and is_state('binary_sensor.house_exits_open_status', 'on')) }}

      - name: "Dashboard Alert: Device Health"
        unique_id: dashboard_alert_device_health
        device_class: problem
        state: >-
          {% set curated = [
            'lock.yale_front_door',
            'alarm_control_panel.vasudha_secure',
            'media_player.lg_webos_tv_oled77c35la',
            'media_player.home_theater',
            'media_player.home_theater_2',
          ] %}
          {{ curated | map('states') | select('in', ['unavailable', 'unknown']) | list | count > 0 }}

      - name: "Dashboard Alert: Override Active"
        unique_id: dashboard_alert_override_active
        device_class: running
        state: >-
          {{ is_state('input_boolean.party_mode', 'on')
             or is_state('input_boolean.automations_paused', 'on') }}
```

Note: the device-health curated list deliberately excludes the zigbee contact/vibration/battery sensors observed `unavailable` live on this instance (mostly decommissioned devices with raw `0xa4c...` ids) — those are noise, not actionable signal. Extend the `curated` list only with devices the user actually relies on daily.

- [ ] **Step 2: Validate against HA's schema**

Run the same `check_config` container command as Task 1, Step 3.
Expected: clean output, no disabled-entity warnings for the three new binary sensors.

- [ ] **Step 3: Commit**

```bash
git add modules/services/home-automation/home-assistant/ha-config/packages/dashboard_ideal_context.yaml
git commit -m "$(cat <<'EOF'
Add security/device-health/override alert sensors for ideal dashboard

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WticZrVkywjzmnsf7inVyF
EOF
)"
```

---

## Task 3: Dashboard top section — personalized + presence-swapped

**Files:**
- Modify: `modules/services/home-automation/home-assistant/ha-config/dashboards/dashboard_ideal.yaml:1-9` (the first `sections` grid, currently the "Rooms" heading + 11 area cards — the area cards move to Task 5, this task only replaces what's *above* them)

**Interfaces:**
- Consumes: `sensor.dashboard_presence_state`, `sensor.dashboard_time_period`, `sensor.dashboard_eta` (Task 1), Arun/Anjali user ids (Global Constraints table)

- [ ] **Step 1: Replace the top of the first grid section**

Insert this new grid section as the *first* section in `views[0].sections`, before the existing "Rooms" grid:

```yaml
  - type: grid
    cards:
    - type: custom:mushroom-template-card
      primary: >-
        {% if is_state('sensor.dashboard_presence_state', 'away') %}
          Away
        {% elif is_state('sensor.dashboard_presence_state', 'home_both') %}
          Everyone's home
        {% else %}
          Home
        {% endif %}
      secondary: >-
        {{ states('sensor.dashboard_time_period') | title }}{% if states('sensor.dashboard_eta') not in ['none', 'unknown', 'unavailable'] %} · {{ states('sensor.dashboard_eta') }}{% endif %}
      icon: >-
        {% if is_state('sensor.dashboard_presence_state', 'away') %}mdi:home-export-outline{% else %}mdi:home-heart{% endif %}
      grid_options:
        columns: full
      visibility:
      - condition: user
        users:
        - a1d4401b8b714ebb83f07c5316ab399c
    - type: custom:mushroom-template-card
      primary: >-
        {% if is_state('sensor.dashboard_presence_state', 'away') %}
          Away
        {% elif is_state('sensor.dashboard_presence_state', 'home_both') %}
          Everyone's home
        {% else %}
          Home
        {% endif %}
      secondary: >-
        {{ states('sensor.dashboard_time_period') | title }}{% if states('sensor.dashboard_eta') not in ['none', 'unknown', 'unavailable'] %} · {{ states('sensor.dashboard_eta') }}{% endif %}
      icon: >-
        {% if is_state('sensor.dashboard_presence_state', 'away') %}mdi:home-export-outline{% else %}mdi:home-heart{% endif %}
      grid_options:
        columns: full
      visibility:
      - condition: user
        users:
        - 6edcc5a09c3144d684077ee362e7394a
    - type: custom:mushroom-template-card
      primary: "Vasudha"
      secondary: >-
        {{ states('sensor.dashboard_presence_state') | replace('_', ' ') | title }} · {{ states('sensor.dashboard_time_period') | title }}
      icon: mdi:home
      grid_options:
        columns: full
      visibility:
      - condition: not
        conditions:
        - condition: user
          users:
          - a1d4401b8b714ebb83f07c5316ab399c
          - 6edcc5a09c3144d684077ee362e7394a
```

(Arun's and Anjali's cards are identical templates here — both key off the same shared sensors; this greeting card is deliberately generic. Per-person area-preference — Arun's office vs Anjali's kitchen/living — is handled in Task 5's room row, where each viewer's `condition: user` keeps their area always visible regardless of occupancy. If distinct greeting wording per person is wanted later, split `primary`/`secondary` per card — the three-card `visibility` skeleton already supports it.)

- [ ] **Step 2: Validate against HA's schema**

Run the `check_config` container command.
Expected: no schema errors for the `mushroom-template-card` blocks (they're plain Lovelace YAML, not validated by `check_config` beyond generic structure — the real check here is Step 3).

- [ ] **Step 3: Manual verification in-browser**

Log in as Arun on `https://ha.karunagath.in/dashboard-ideal/0` → see the Arun-conditioned card. Log in as Anjali (or use a private window) → see the Anjali-conditioned card. Log out / use an unauthenticated or third-account session → see the neutral "Vasudha" card. Confirm the `secondary` text changes between the three known `dashboard_presence_state` values reachable in practice (`home_both` when both are home; toggle a `person.*` to `not_home` via Developer Tools → States to check `away`/`home_arun`/`home_anjali` without leaving the house).

- [ ] **Step 4: Commit**

```bash
git add modules/services/home-automation/home-assistant/ha-config/dashboards/dashboard_ideal.yaml
git commit -m "$(cat <<'EOF'
Add personalized presence-aware top section to ideal dashboard

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WticZrVkywjzmnsf7inVyF
EOF
)"
```

---

## Task 4: Actionable-now feed (replaces Environment + Security sections)

**Files:**
- Modify: `modules/services/home-automation/home-assistant/ha-config/dashboards/dashboard_ideal.yaml` — replace the current second grid section (`Environment`, lines ~54-113 pre-Task-3) and third grid section (`Security`, lines ~114-162 pre-Task-3) with one combined section. Line numbers shift after Task 3's insert; locate by the `heading: Environment` / `heading: Security` text instead of a fixed line range.

**Interfaces:**
- Consumes: `binary_sensor.dashboard_alert_security`, `binary_sensor.dashboard_alert_device_health`, `binary_sensor.dashboard_alert_override_active` (Task 2), plus the pre-existing `lock.yale_front_door`, `alarm_control_panel.vasudha_secure`, `binary_sensor.house_exits_open_status`, `sensor.average_temperature`/`average_humidity`/`average_illuminance`

- [ ] **Step 1: Replace the Environment + Security grid sections with one Actionable-Now section**

```yaml
  - type: grid
    cards:
    - type: heading
      heading: Right Now
      heading_style: title
      badges:
      - type: entity
        entity: binary_sensor.dashboard_alert_security
        show_state: false
        visibility:
        - condition: state
          entity: binary_sensor.dashboard_alert_security
          state: "on"
      - type: entity
        entity: binary_sensor.dashboard_alert_device_health
        show_state: false
        visibility:
        - condition: state
          entity: binary_sensor.dashboard_alert_device_health
          state: "on"
      - type: entity
        entity: binary_sensor.dashboard_alert_override_active
        show_state: false
        visibility:
        - condition: state
          entity: binary_sensor.dashboard_alert_override_active
          state: "on"
    - type: entities
      title: Needs attention
      show_header_toggle: false
      visibility:
      - condition: or
        conditions:
        - condition: state
          entity: binary_sensor.dashboard_alert_security
          state: "on"
        - condition: state
          entity: binary_sensor.dashboard_alert_device_health
          state: "on"
        - condition: state
          entity: binary_sensor.dashboard_alert_override_active
          state: "on"
      entities:
      - entity: binary_sensor.house_exits_open_status
        name: Open door/window
        visibility:
        - condition: state
          entity: binary_sensor.dashboard_alert_security
          state: "on"
      - entity: alarm_control_panel.vasudha_secure
        visibility:
        - condition: state
          entity: binary_sensor.dashboard_alert_security
          state: "on"
      - entity: binary_sensor.dashboard_alert_device_health
        name: Device unavailable
        visibility:
        - condition: state
          entity: binary_sensor.dashboard_alert_device_health
          state: "on"
      - entity: input_boolean.party_mode
        visibility:
        - condition: state
          entity: binary_sensor.dashboard_alert_override_active
          state: "on"
      - entity: input_boolean.automations_paused
        visibility:
        - condition: state
          entity: binary_sensor.dashboard_alert_override_active
          state: "on"
    - type: markdown
      content: "Nothing needs attention right now."
      visibility:
      - condition: and
        conditions:
        - condition: state
          entity: binary_sensor.dashboard_alert_security
          state: "off"
        - condition: state
          entity: binary_sensor.dashboard_alert_device_health
          state: "off"
        - condition: state
          entity: binary_sensor.dashboard_alert_override_active
          state: "off"
    - type: entity
      entity: sensor.average_temperature
      name: Temperature
    - type: entity
      entity: sensor.average_humidity
      name: Humidity
    - type: entity
      entity: sensor.average_illuminance
      name: Illuminance
```

The `custom:alarmo-card` and `script.alarm_force_arm_night` button from the old Security section are dropped here (they duplicate controls already on the existing "Home" dashboard) — full alarm control stays on "Home"; this dashboard surfaces alarm *state* only when it's part of what needs attention. If that's wrong, keep them as two more always-visible cards appended to this section.

- [ ] **Step 2: Validate against HA's schema**

Run the `check_config` container command.
Expected: no errors. Note `check_config` does not evaluate Lovelace card correctness — this only confirms the YAML is well-formed and the referenced entities exist.

- [ ] **Step 3: Manual verification in-browser**

With nothing currently alerting, confirm the "Nothing needs attention right now" markdown shows and the entities list is hidden. Toggle `input_boolean.party_mode` on via Developer Tools → States, refresh the dashboard, confirm the "Needs attention" card appears with the Party Mode row and the corresponding badge shows. Toggle it back off.

- [ ] **Step 4: Commit**

```bash
git add modules/services/home-automation/home-assistant/ha-config/dashboards/dashboard_ideal.yaml
git commit -m "$(cat <<'EOF'
Replace static Environment/Security sections with actionable-now feed

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WticZrVkywjzmnsf7inVyF
EOF
)"
```

---

## Task 5: Compact, relevance-filtered room row

**Files:**
- Modify: `modules/services/home-automation/home-assistant/ha-config/dashboards/dashboard_ideal.yaml` — replace the 11 `type: area` cards (now the second grid section, after Task 3's insert) with per-room `tile` cards carrying `visibility:` conditions.

**Interfaces:**
- Consumes: the occupancy-status/light entities listed in the Global Constraints "Verified facts" table

- [ ] **Step 1: Replace the area-card grid with tile cards**

```yaml
  - type: grid
    cards:
    - type: heading
      heading: Active Rooms
      heading_style: title
    - type: tile
      entity: light.kitchen_light_1
      area: kitchen
      features:
      - type: light-brightness
      visibility:
      - condition: or
        conditions:
        - condition: state
          entity: binary_sensor.kitchen_occupancy_status
          state: "on"
        - condition: state
          entity: light.kitchen_light_1
          state: "on"
        - condition: user
          users:
          - 6edcc5a09c3144d684077ee362e7394a
    - type: tile
      entity: light.kitchen_dining_light_1
      area: kitchen_dining_room
      features:
      - type: light-brightness
      visibility:
      - condition: state
        entity: light.kitchen_dining_light_1
        state: "on"
    - type: tile
      entity: light.dining_room_light_1
      area: dining_room
      features:
      - type: light-brightness
      visibility:
      - condition: or
        conditions:
        - condition: state
          entity: binary_sensor.dining_room_occupancy_status
          state: "on"
        - condition: state
          entity: light.dining_room_light_1
          state: "on"
    - type: tile
      entity: light.tv_backlight
      area: living_room
      features:
      - type: light-brightness
      visibility:
      - condition: or
        conditions:
        - condition: state
          entity: binary_sensor.living_room_occupancy_status
          state: "on"
        - condition: state
          entity: light.tv_backlight
          state: "on"
        - condition: state
          entity: media_player.lg_webos_tv_oled77c35la
          state: playing
        - condition: user
          users:
          - 6edcc5a09c3144d684077ee362e7394a
    - type: tile
      entity: light.hall
      area: hall
      features:
      - type: light-brightness
      visibility:
      - condition: or
        conditions:
        - condition: state
          entity: binary_sensor.hallway_occupancy_status
          state: "on"
        - condition: state
          entity: light.hall
          state: "on"
    - type: tile
      entity: light.bedroom_wardrobe_light_1
      area: bedroom
      features:
      - type: light-brightness
      visibility:
      - condition: or
        conditions:
        - condition: state
          entity: binary_sensor.bed_room_occupancy_status
          state: "on"
        - condition: state
          entity: light.bedroom_wardrobe_light_1
          state: "on"
    - type: tile
      entity: light.office_room_light
      area: office
      features:
      - type: light-brightness
      visibility:
      - condition: or
        conditions:
        - condition: state
          entity: light.office_room_light
          state: "on"
        - condition: user
          users:
          - a1d4401b8b714ebb83f07c5316ab399c
    - type: tile
      entity: sensor.average_temperature
      area: bathroom
      visibility:
      - condition: state
        entity: binary_sensor.bathroom_occupancy_status
        state: "on"
    - type: tile
      entity: sensor.average_temperature
      area: laundry
      visibility:
      - condition: state
        entity: binary_sensor.laundry_room_occupancy_status
        state: "on"
    - type: tile
      entity: lock.yale_front_door
      area: front
    - type: tile
      entity: sensor.average_temperature
      area: toilet
```

Notes:
- `front` and `toilet` have no occupancy/light signal (per Global Constraints table) so they're always shown — 2 of 11 tiles, not the full flat grid the spec objected to.
- `office` always shows to Arun's login, `kitchen`/`living_room` always show to Anjali's login (each via an added `condition: user` OR-branch), regardless of occupancy — this is the per-person area-preference from the spec's presence-aware section (his office / her kitchen-living), expressed as always-relevant-to-that-viewer rather than a distinct row ordering, since a `sections` grid can't reorder per viewer without duplicating the whole row.
- `bathroom`/`laundry`/`toilet` have no dedicated light entity in the registry dump; they use `sensor.average_temperature` as the tile's primary entity purely to have something numeric to display alongside the `area:` icon/name — swap in a room-specific entity if one exists that wasn't caught by the light/occupancy query (re-check via the same `config/entity_registry/list` WS call used during planning if this looks wrong once deployed).
- `type: tile` with an `area:` key shows the area name/picture as context while the `entity:` key drives the live state shown — this is different from the old `type: area` card and was chosen specifically because `type: area` was the component confirmed non-interactive/data-less in the original bug report.

- [ ] **Step 2: Validate against HA's schema**

Run the `check_config` container command.
Expected: no errors.

- [ ] **Step 3: Manual verification in-browser**

With the house in its current occupied/unoccupied state, load `/dashboard-ideal/0` and confirm only rooms matching their visibility condition render (fewer than 11 tiles unless everything happens to be active). Walk into a room with a `binary_sensor.*_occupancy_status` sensor (or toggle it via Developer Tools → States) and confirm its tile appears; leave and confirm it disappears once occupancy clears (may lag by the sensor's own clear-delay).

- [ ] **Step 4: Commit**

```bash
git add modules/services/home-automation/home-assistant/ha-config/dashboards/dashboard_ideal.yaml
git commit -m "$(cat <<'EOF'
Replace flat area-tile grid with relevance-filtered room row

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WticZrVkywjzmnsf7inVyF
EOF
)"
```

---

## Task 6: Full validation, PR

**Files:** none (validation + PR only)

- [ ] **Step 1: Full structural validation**

Run: `nix flake check` and `nix develop -c just build sutala` from repo root.
Expected: both succeed with no errors.

- [ ] **Step 2: Full HA schema validation**

Run the containerized `check_config` script (full mount set per root `CLAUDE.md`) once more against the complete set of changes.
Expected: clean output — no "Failed config" or "could not be validated and has been disabled" lines anywhere, including for `dashboard_ideal_context.yaml` and `dashboard_ideal.yaml`.

- [ ] **Step 3: Full manual walkthrough**

Repeat the manual verification steps from Tasks 3-5 in one pass on the deployed dashboard: personalization (3 viewer variants), actionable-now feed (empty + at-least-one-alert states), room row (relevance filtering). Confirm the existing "Home" dashboard is untouched and still fully functional.

- [ ] **Step 4: Push and open PR**

```bash
git push -u origin ha-dashboard-fixes
gh pr create --title "Redesign Home (Ideal) dashboard: actionable, time/presence/viewer-aware" --body "$(cat <<'EOF'
## Summary
- Replaces the flat, data-less 11-area-tile grid in dashboard_ideal.yaml with a dashboard that surfaces what's actionable now instead of an inventory
- New packages/dashboard_ideal_context.yaml computes time-of-day, presence, ETA, and three alert booleans once, consumed via native Lovelace `visibility:` conditions
- Top section is personalized per logged-in HA user (Arun / Anjali / neutral shared-device fallback), cross-referenced with live presence
- Room row is relevance-filtered (occupied or active) instead of listing all 11 areas flatly
- Runs side-by-side with the existing "Home" dashboard — no changes to it

## Test plan
- [x] `nix flake check`
- [x] `just build sutala`
- [x] Containerized HA `check_config` script — clean output
- [x] Manual browser walkthrough: personalization, actionable-now feed, room-row filtering
- Affected host: sutala (Home Assistant container only)

Design spec: docs/superpowers/specs/2026-09-04-ha-ideal-dashboard-design.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01WticZrVkywjzmnsf7inVyF
EOF
)"
```

Report the PR URL back to the user.
