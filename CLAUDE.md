# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

Enter the devShell first for access to `age`, `colmena`, `just`, `nixos-rebuild`, `sops`, `ssh-to-age`:
```sh
nix develop
```

All task commands use `just`:
```sh
just fmt                              # Format all Nix files (treefmt / nix fmt)
just check                            # Validate flake (nix flake check)
just update                           # Update flake.lock inputs
just build [host]                     # Build host config (default: sutala)
just switch [host]                    # Apply config locally (nixos-rebuild / darwin-rebuild)
just switch-remote [host] [target]    # Apply via SSH with sudo
just deploy [host]                    # Deploy using colmena
just sops-edit [file]                 # Edit an encrypted secrets file
```

Run `nix flake check` as the primary validation before committing.

## Architecture

### Hosts
- **`hosts/sutala/`** — NixOS x86_64-linux home server (192.168.1.10, LAN if `enp2s0`). Media, home-automation, DNS, monitoring, surveillance. Disk layout via `disko.nix`; deployed both as a `nixosConfigurations` entry and as the sole `colmena` node (`flake.nix`).
- **`hosts/mac-work/`** — nix-darwin aarch64-darwin laptop, single `default.nix` (no separate `darwin-configuration.nix`). Home Manager user `akarunagath`, imports `modules/home/work.nix`.

### Module Layout
This repo follows the **dendritic pattern**: every `.nix` file under `modules/` is itself a flake-parts module that self-registers into a flat registry — `flake.nixosModules.<name>` / `flake.darwinModules.<name>` / `flake.homeManagerModules.<name>` / `flake.lib.<name>` / `flake.overlays.<name>` — rather than being pulled in via a hand-maintained `imports` list. `flake.nix` walks the whole tree with a single `(inputs.import-tree ./modules).imports` call; nothing under `modules/` is referenced from `flake.nix` by literal path. **Exception:** `modules/flake-lib.nix`, `modules/flake-darwin-modules.nix`, and `modules/flake-home-manager-modules.nix` declare the `flake.lib` / `flake.darwinModules` / `flake.homeManagerModules` registries themselves (the latter two also carry the `apply` wrapper that stamps `_class`/`_file`) — they don't register as entries in one. (`flake.nixosModules` is flake-parts' own built-in registry, not something this repo declares.)

**Naming rule (load-bearing — follow exactly when adding a file):** a module's registered name is flat — its path relative to `modules/`, with `/` replaced by `-` and `.nix` stripped, no special-casing of `default.nix`. E.g. `modules/services/system/nix-allow-unfree.nix` → `flake.nixosModules.services-system-nix-allow-unfree`; `modules/home/git/delta.nix` → `flake.homeManagerModules.home-git-delta`. **Exception:** `flake.lib` and `flake.overlays` name relative to their *own* directory instead (to avoid stuttering, since the registry name already equals the directory name) — `modules/lib/container/definition.nix` → `flake.lib.container-definition`, not `flake.lib.lib-container-definition`.

Hosts, containers, and home-manager configs consume registered modules **by name only**, never by literal path — `flakeModules.nixos.<name>` / `flakeModules.darwin.<name>` / `flakeModules.homeManager.<name>` (and `flakeLib.<name>` for lib helpers), threaded in via `specialArgs` (top-level host and colmena), `containers.<name>.specialArgs` (podman/nspawn containers — never inherited automatically from the host, must be explicitly re-threaded), or `home-manager.extraSpecialArgs`.

- **`modules/home/`** — Home Manager dotfiles shared across hosts (git, vim, tmux, fzf, zoxide, sesh, gh, claude-code, mcp-nixos, etc.), as flat leaf modules with no shared aggregator or `dotfiles.*` options. Each host's own `imports` list picks which leaves it wants and sets Catppuccin/`home.stateVersion` itself (`hosts/sutala/home.nix`, `hosts/mac-work/default.nix`). `work.nix` (git `~/.gitconfig.work` include, ripgrep credential-file exclusions) is opt-in per host.
- **`modules/services/`** — NixOS system services, one subdir per concern: `proxy/` (nginx), `dns/` (AdGuard Home + Unbound), `monitoring/` (Prometheus/Grafana/Loki), `infrastructure/` (ACME, OpenSSH, sops), `discovery/` (Avahi), `surveillance/` (NVR + proxy), `virtualisation/` (Podman, Arcane), `system/` (nix.conf, sysadmin, vim), plus `tailscale.nix`, `postgres.nix`, `redis.nix`, `mosquitto.nix`, `zigbee2mqtt.nix`, `niri.nix`.
- **`modules/hardware/`** — host-specific hardware support, registered flat, e.g. `modules/hardware/intel-igpu.nix` → `flake.nixosModules.hardware-intel-igpu`, consumed by `hosts/sutala/configuration.nix`.
- **`modules/containers/`** — Podman quadlet stacks, each with its own subnet in `vars.nix`: `life/` (actualbudget, ghostfolio), `media-mgmt/` (arr-stack: radarr/sonarr/lidarr/bazarr/prowlarr/sabnzbd/etc.), `home-auto/` (home-assistant, matter-server, music-assistant, otbr), plus `monitoring.nix` and `media-play.nix`. Shared helpers in `common.nix`.
- **`modules/fail2ban.nix`** — intrusion prevention, registered flat as `flake.nixosModules.fail2ban` (no directory prefix, same shape as `vars`).
- **`modules/users/`** — User accounts (`kra3.nix` primary user, `root.nix`). Each user module embeds its own Home Manager config.
- **`modules/vars.nix`** — Single source of truth (deliberately kept at module root, not nested, since it's cross-cut by hosts/containers/services/infrastructure): LAN interface/CIDR, per-container-stack Podman subnets and host/local veth addresses, ACME email/domain.
- **`modules/overlays/`** — Custom nixpkgs patches (intel-media-sdk C++17 fix for iGPU), wired in via `flake.self.overlays.default`.
- **`modules/lib/`** — Helper functions: `container/` (quadlet definition), `deployment/` (hardening).

**Not every registered module is host-agnostic.** The registry's flatness doesn't imply interchangeability — some entries are written for one specific host or container's own evaluation and would misbehave if imported elsewhere. E.g. `containers-common` sets container-specific defaults (`mkForce`, a pinned `stateVersion`); `users-kra3` embeds a sutala-specific path (`hosts/sutala/home.nix`). Check what a module actually assumes before reusing it on a different host.

**A shared name prefix does not imply an import relationship.** Flat names can look like a parent/children hierarchy that doesn't exist — e.g. `containers-home-auto` and `containers-home-auto-home-assistant-default` share a prefix but are independent siblings in `hosts/sutala/configuration.nix`'s own import list; the former's container config does not import the latter. Treat a shared prefix as naming convention only, never as evidence of an import relationship.

### Key Patterns
- **flake-parts:** `flake.nix` uses flake-parts for output composition. New outputs go under the `flake` section; system-specific config under `perSystem`.
- **Dendritic self-registration:** every `modules/**/*.nix` file registers itself into a flat flake-parts registry (see Module Layout above) instead of being named in a host's `imports` list by literal path — adding a new module is "create the file," not "create the file and also wire it in three places."
- **User-land vs system:** User packages and dotfiles live in `modules/home/` (imported per-user via `modules/users/*.nix`); system packages go in `environment.systemPackages` in host or service modules.
- **Secrets:** sops-nix with age encryption. Host SSH keys are the recipients (see `.sops.yaml`). Use nested keys (e.g. `users.kra3.password`, `cloudflare.acme.token`). Edit with `just sops-edit <file>`.
- **Containers:** Podman + quadlet-nix. Each stack has its own veth bridge subnet defined in `modules/vars.nix`.
- **Stable + unstable:** Both `nixpkgs` (`nixos-26.05`) and `nixpkgs-unstable` are inputs; unstable packages are accessible via the overlay or `pkgs.unstable`.
- **Theming:** Catppuccin Mocha applied via the home-manager catppuccin module, set per-host (`hosts/sutala/home.nix`, `hosts/mac-work/default.nix`).

## Coding Style
- 2-space indentation, trailing commas in multi-line lists/attrsets, one attribute per line for large sets.
- Lowercase names with hyphens or underscores (e.g. `hardware-configuration.nix`).
- Run `just fmt` before committing.

## Commits & PRs
- Short imperative commit messages scoped to one host or module (e.g. `Add laptop NixOS profile`).
- PRs: describe what changed, list commands run (e.g. `nix flake check`), call out affected hosts.

## Verification
Before asserting file or config state, re-read it and reference the verification. If you cannot verify, say so.
