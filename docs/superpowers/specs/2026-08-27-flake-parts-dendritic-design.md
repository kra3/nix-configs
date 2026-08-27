# flake-parts / dendritic pattern migration

Status: approved design, not yet implemented.
Baseline: `main`/`release` at `e17c754` (2026-08-27), 105 module files.

## Motivation

The repo already imports `flake-parts` but only uses it for `perSystem`
(treefmt, devShell). Host wiring (`nixosConfigurations`, `darwinConfigurations`,
`colmena`) is hand-built by a `buildEach` helper reading `flake/hosts.nix`, and
every module under `modules/` is a plain NixOS/darwin/home-manager module
pulled in by an explicit `imports = [ ... ]` list on each host/container file.

Three things about that are getting worse as the repo grows:

- Adding a module means editing a host or container's `imports` list, not just
  adding a file. `modules/lib/default.nix` shows the same problem one layer
  down — a manually maintained re-export list that grows every time a new lib
  helper is added (most recently in PR #13, which added `quadlet.nix`,
  `nginx.nix`, `observability.nix` and three matching lines to `default.nix`).
- A module can only be one thing (NixOS-only, darwin-only, home-manager-only).
  There's no way for one file to contribute to more than one class without
  either duplicating content or building custom plumbing.
- `flake/hosts.nix` + `buildEach` is a hand-rolled stand-in for wiring
  flake-parts would give natively.

Goal: adopt the "dendritic" pattern — every leaf module is a flake-parts
module contributing to `flake.modules.<class>.<name>` (or `flake.overlays.*`,
`flake.lib.*`), auto-discovered via `import-tree` — so adding a feature is
"add a file," and each host/container opts into a short, explicit,
semantic list of named features instead of a long list of file paths.

## Non-goals

- Not changing any host's actual runtime behavior. Every step through the
  migration is drv-identical unless explicitly called out (none are).
- Not touching the niri.nix split (tracked separately, task #17) — the two
  are independent and may interleave.
- Not preserving `drv-lock.json`/the `refactor-guard` CI job long-term — it's
  scaffolding for this migration's own verification, removed in the final
  step (see "CI discipline" below).

## Architecture

### Two-tier model: registration vs. consumption

`import-tree` walks a directory and imports every `.nix` file in it as a
flake-parts module. That only handles **registration** — each file declares
something under `flake.modules.<class>.<name>` (or `flake.overlays.<name>`,
`flake.lib.<path>`). It says nothing about who uses it.

**Consumption stays an explicit, per-consumer list** — this is deliberate,
not a compromise. Each host and each container keeps its own short list of
named modules it opts into, e.g.:

```nix
# hosts/sutala/configuration.nix (after)
{ config, ... }:
{
  imports = with config.flake.modules.nixos; [
    default            # always-on shared base (nix settings, vars schema, ...)
    nix-allow-unfree    # opt-in
    niri
    monitoring-container
    media-play-container
    home-auto-container
    # ...
  ];
}
```

```nix
# hosts/mac-work/default.nix (after)
{ config, ... }:
{
  imports = with config.flake.modules.darwin; [
    default
    # no niri, no unfree — never registered under darwin.* in the first
    # place, so it can't land here by accident
  ];
}
```

A nixos-only module is registered under `flake.modules.nixos.*` and simply
doesn't exist under `flake.modules.darwin.*` — cross-platform leakage is a
type error, not a discipline problem. This preserves the opt-in-not-accidental
principle from the nix-settings-split (`nix-allow-unfree`, `nix-autoupgrade`
stay individually named; only genuinely-everywhere things like
`nix.settings.experimental-features` fold into a `default` aggregate).

Containers (`monitoring`, `media-play`, `home-auto`, and the nested
`containers.<name>.config` pods under `home-auto/*`, `media-mgmt/*`, `life/*`)
are conceptually independent machines that happen to be nested NixOS
evaluations inside sutala's own `nixosSystem` build. `flake.modules.nixos.*`
values are plain NixOS modules, so they're consumed identically inside
`containers.<name>.config.imports` — a container opts into both its software
stack (`bazarr`, `sonarr`, ...) and cross-cutting concerns (`nginx-vhost`,
`observability-alloy`, `quadlet-network-deps`) from the same namespace, same
mechanism, same explicit list.

### Directory scope — not everything is a leaf module

`import-tree` expects every file it walks to be a flake-parts module
(`{ config, lib, ... }: { flake.modules... = ...; }`). Three subtrees don't
fit that shape directly and need their own treatment:

| Subtree | Current shape | Treatment |
|---|---|---|
| `modules/services/`, `modules/containers/`, `modules/hardware/`, `modules/users/`, `modules/home/`, `modules/vars.nix` | Plain NixOS/darwin/home-manager modules | Converted to `flake.modules.<class>.<name>`, auto-discovered |
| `modules/overlays/*.nix` | Plain overlay functions (`final: prev: ...`) | Converted to `flake.overlays.<name>`, auto-discovered (flake-parts' native overlay slot) |
| `modules/lib/**/*.nix` | Plain helper functions, manually re-exported by `modules/lib/default.nix` | Converted to `flake.lib.<namespace>.<name>`, auto-discovered; `default.nix` deleted |

All three end up auto-discovered by the same `import-tree ./modules` call in
`flake.nix` — the distinction is only which `flake.*` attribute each file
contributes to, not a separate discovery mechanism.

`modules/vars.nix` is a special case: it's an options *schema*
(`vars.network`, `vars.acme`, ...), not an opt-in feature. It's registered
like any other module but lives in the `default` aggregate every host/
container pulls in, rather than being individually named.

### Overlays

`overlays.default` in `flake.nix` changes from `import ./modules/overlays` to
`lib.composeManyExtensions (builtins.attrValues config.flake.overlays)`. Adding
a new overlay is then "add a file under `modules/overlays/`," same as any
other module — no more manual composition in `modules/overlays/default.nix`.

### Lib helpers

Each file under `modules/lib/` (currently `container/definition.nix`,
`deployment/hardening.nix`, `quadlet.nix`, `nginx.nix`, `observability.nix`)
becomes a flake-parts module contributing to `flake.lib.<namespace>.<name>`
(e.g. `flake.lib.containers.quadlet`, `flake.lib.deployment.hardening`).

Consumers stop doing `import ../../lib { inherit lib; }` per-file. Instead,
the host-building layer adds `flakeLib = config.flake.lib;` to `specialArgs`
(alongside the existing `inputs`), so any module can take `{ flakeLib, ... }:`
and call e.g. `flakeLib.containers.quadlet.mkHealthCheck { ... }`.
`modules/lib/default.nix` is deleted — there's nothing left for it to
aggregate.

### Host/colmena wiring

`flake/hosts.nix` + `buildEach` is replaced by flake-parts option data: hosts
become entries under a small `options.hosts` submodule (system, class,
identity), and `flake.nixosConfigurations`/`flake.darwinConfigurations` are
built by mapping over that, pulling each host's module list from
`config.flake.modules.<class>` by name rather than by file path.

Colmena's `sutala` node currently reuses `hosts.sutala.modules` verbatim plus
a small colmena-specific shim (the `nixpkgs.flake.source` /
`system.nixos.versionSuffix` / `system.nixos.revision` block, needed because
colmena bypasses the flake's own `nixosSystem` wrapper). That shim carries
over unchanged — colmena's node definition pulls the same named module list
sutala's `nixosConfigurations` entry does, plus the same shim module appended
at the end.

## CI discipline through the migration

Every step is drv-identical by construction: each step either (a) changes
*how* a module is addressed without changing its content (wrapping in
`flake.modules.<class>.<name> = { ...unchanged body... }`), or (b) changes
*how* a host/container assembles its module list without changing *which*
modules end up in it. `drv-lock.json` and the `refactor-guard` CI job — both
already in place from the nix-settings-split work — keep gating every PR
through the migration exactly as before: a step that unexpectedly moves a
host's drvPath fails CI, full stop, no step in this plan is expected to
touch `drv-lock.json`.

**Final step only:** once the migration is complete, delete `drv-lock.json`,
remove the `refactor-guard` job from `.github/workflows/check.yml` (keep
`flake-check` and `eval-hosts` — those aren't drv-lock-dependent), and update
`CLAUDE.md`/`README.md` to describe the dendritic structure. This tooling was
built for this migration's own verification, not meant to be permanent repo
infrastructure — confirmed explicitly, not left behind by default.

## Commit stack

Each numbered item is its own worktree/branch/PR, merged and drv-verified
before the next starts (per this repo's established workflow: `just drv`/
`just eval`, Sonnet implementor + Haiku verifier + Opus adversarial review on
anything nontrivial, small commits).

1. **Add `import-tree`, wire registration only.** New flake input
   (`inputs.import-tree`). `flake.nix` gains
   `imports = [ ... ] ++ (inputs.import-tree ./modules).imports` scoped to
   exclude nothing yet — but no module content changes. This step alone
   doesn't compile until step 2 also lands (nothing consumes `flake.modules.*`
   yet), so 1 and 2 may need to be a single PR in practice — decide during
   implementation planning whether they split cleanly or must land together.
2. **Convert `flake/hosts.nix` + `buildEach` to flake-parts host
   composition.** Mechanical: every existing module file gets wrapped in
   `flake.modules.<class>.<name> = { <unchanged body> };`; every host/
   container's file-path `imports` list becomes a name-based
   `with config.flake.modules.<class>; [ ... ]` list referencing the same set
   of modules. drv-identical — same modules, same order semantics, different
   addressing.
3. **Convert `modules/home/*`.** Lowest risk: home-manager only, no host
   toplevel changes, easiest to verify (`home-manager build` per user
   diverges less than a full host toplevel).
4. **Convert `modules/overlays/*` and `modules/lib/**`,** including the
   `flakeLib` specialArgs change and deleting `modules/lib/default.nix`.
5. **Convert `modules/services/system/*`,** the four files from the
   nix-settings-split (`nix-defaults-nixos`, `nix-defaults-darwin`,
   `nix-allow-unfree`, `nix-autoupgrade`) — small, already well-understood,
   good validation of the opt-in-list model end to end.
6. **Convert remaining `modules/services/*`** (dns, monitoring, media,
   infrastructure, proxy, surveillance, virtualisation, tailscale, etc).
7. **Convert `modules/containers/*`** (monitoring, media-play, home-auto,
   media-mgmt/*, life/*, home-auto/*) — last because these are the most
   numerous and most likely to surface an edge case in the nested
   `containers.<name>.config` consumption path.
8. **Convert `modules/hardware/*`, `modules/users/*`, `modules/vars.nix`.**
9. **Cleanup:** delete `drv-lock.json`, remove `refactor-guard` from
   `check.yml`, update `CLAUDE.md`/`README.md`.

Steps 3 through 8 can reorder freely relative to each other if a different
sequence turns out more convenient during implementation — none depend on
the others' internal content, only on steps 1-2 having landed first.

## Verification per step

Same discipline as the nix-settings-split: `nix eval --raw
.#nixosConfigurations.sutala.config.system.build.toplevel.drvPath` (and the
darwin/colmena equivalents) before and after each step, comparing against
`drv-lock.json`. CI's `refactor-guard` job enforces this automatically on
every PR through step 8; step 9 removes that job once there's nothing left
for it to guard.

## Open question for implementation planning

Whether steps 1 and 2 must land as a single PR (since registering modules
under `flake.modules.*` with no consumer is likely to fail `nix flake check`
on unused-but-declared option paths, or simply because host files still
reference the old `flake/hosts.nix` shape until step 2 rewires them) — to be
resolved when writing the implementation plan, not blocking spec approval.
