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
- **`hosts/mac-work/`** — nix-darwin aarch64-darwin laptop, single `default.nix` (no separate `darwin-configuration.nix`). Home Manager user `akarunagath`, `dotfiles.work = true`.

### Module Layout
- **`modules/home/`** — Home Manager dotfiles shared across hosts (git, vim, tmux, fzf, zoxide, sesh, gh, claude-code, mcp-nixos, etc.). `default.nix` exposes options `dotfiles.desktop`, `dotfiles.work`, `dotfiles.githubUser` and turns on Catppuccin (mocha/blue) for every user.
- **`modules/services/`** — NixOS system services, one subdir per concern: `proxy/` (nginx), `dns/` (AdGuard Home + Unbound), `monitoring/` (Prometheus/Grafana/Loki), `infrastructure/` (ACME, OpenSSH, sops), `discovery/` (Avahi), `surveillance/` (NVR + proxy), `virtualisation/` (Podman, Arcane), `system/` (nix.conf, sysadmin, vim), plus `tailscale.nix`, `postgres.nix`, `redis.nix`, `mosquitto.nix`, `zigbee2mqtt.nix`, `niri.nix`.
- **`modules/containers/`** — Podman quadlet stacks, each with its own subnet in `vars.nix`: `life/` (actualbudget, ghostfolio), `media-mgmt/` (arr-stack: radarr/sonarr/lidarr/bazarr/prowlarr/sabnzbd/etc.), `home-auto/` (home-assistant, matter-server, music-assistant, otbr), plus `monitoring.nix` and `media-play.nix`. Shared helpers in `common.nix`.
- **`modules/users/`** — User accounts (`kra3.nix` primary user, `root.nix`). Each user module embeds its own Home Manager config.
- **`modules/vars.nix`** — Single source of truth (deliberately kept at module root, not nested, since it's cross-cut by hosts/containers/services/infrastructure): LAN interface/CIDR, per-container-stack Podman subnets and host/local veth addresses, ACME email/domain.
- **`modules/overlays/`** — Custom nixpkgs patches (intel-media-sdk C++17 fix for iGPU), wired in via `flake.self.overlays.default`.
- **`modules/lib/`** — Helper functions: `container/` (quadlet definition + integration), `deployment/` (hardening, monitoring, networking, storage), `utils/` (systemd, types).

### Key Patterns
- **flake-parts:** `flake.nix` uses flake-parts for output composition. New outputs go under the `flake` section; system-specific config under `perSystem`.
- **Import-only composition:** Use plain `imports = []` lists — no helper wrappers. Host configs own all further imports (home-manager, disko, sops-nix). Pass `inputs` via `specialArgs`/`extraSpecialArgs`.
- **User-land vs system:** User packages and dotfiles live in `modules/home/` (imported per-user via `modules/users/*.nix`); system packages go in `environment.systemPackages` in host or service modules.
- **Secrets:** sops-nix with age encryption. Host SSH keys are the recipients (see `.sops.yaml`). Use nested keys (e.g. `users.kra3.password`, `cloudflare.acme.token`). Edit with `just sops-edit <file>`.
- **Containers:** Podman + quadlet-nix. Each stack has its own veth bridge subnet defined in `modules/vars.nix`.
- **Stable + unstable:** Both `nixpkgs` (`nixos-26.05`) and `nixpkgs-unstable` are inputs; unstable packages are accessible via the overlay or `pkgs.unstable`.
- **Theming:** Catppuccin Mocha applied globally via the home-manager catppuccin module (set in `modules/home/default.nix`, not per-host).

## Coding Style
- 2-space indentation, trailing commas in multi-line lists/attrsets, one attribute per line for large sets.
- Lowercase names with hyphens or underscores (e.g. `hardware-configuration.nix`).
- Run `just fmt` before committing.

## Commits & PRs
- Short imperative commit messages scoped to one host or module (e.g. `Add laptop NixOS profile`).
- PRs: describe what changed, list commands run (e.g. `nix flake check`), call out affected hosts.

## Verification
Before asserting file or config state, re-read it and reference the verification. If you cannot verify, say so.
