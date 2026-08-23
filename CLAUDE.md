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
- **`hosts/sutala/`** — NixOS x86_64-linux home server (192.168.1.10). Media, home-automation, DNS, monitoring. Disk layout via `disko.nix`.
- **`hosts/mac-work/`** — nix-darwin aarch64-darwin laptop (user: akarunagath). Timezone: `Europe/Copenhagen`; servers use `UTC`.

### Module Layout
- **`modules/home/`** — Home Manager dotfiles shared across hosts. Exposes options: `dotfiles.desktop`, `dotfiles.work`, `dotfiles.githubUser`.
- **`modules/services/`** — NixOS system services: nginx reverse proxy, AdGuard Home + Unbound DNS, Prometheus/Grafana/Loki, ACME/Let's Encrypt, OpenSSH, Tailscale, etc.
- **`modules/containers/`** — Podman quadlet stacks: `monitoring.nix`, `media-play.nix`, `media-mgmt/`, `home-auto/`. Shared helpers in `common.nix`.
- **`modules/users/`** — User accounts (`kra3.nix` primary user, `root.nix`). Each user module embeds its own Home Manager config.
- **`modules/vars.nix`** — Single source of truth: LAN interface, host IPs, Podman subnet/veth addresses, ACME config, DNS settings.
- **`modules/overlays/`** — Custom nixpkgs patches (intel-media-sdk C++17 fix for iGPU).
- **`modules/lib/`** — Container helper library functions.

### Key Patterns
- **flake-parts:** `flake.nix` uses flake-parts for output composition. New outputs go under the `flake` section; system-specific config under `perSystem`.
- **Import-only composition:** Use plain `imports = []` lists — no helper wrappers. `flake.nix` lists only `hosts/<hostname>/configuration.nix`; host configs own all further imports (home-manager, disko, sops-nix). Pass `inputs` via `specialArgs`.
- **User-land vs system:** User packages and dotfiles live in `modules/users/<user>.nix`; system packages go in `environment.systemPackages` in host or service modules.
- **Secrets:** sops-nix with age encryption. Host SSH keys are the recipients (see `.sops.yaml`). Use nested keys (e.g. `users.kra3.password`, `cloudflare.acme.token`). Edit with `just sops-edit <file>`.
- **Containers:** Podman + quadlet-nix. Each stack has its own veth bridge subnet defined in `modules/vars.nix`.
- **Stable + unstable:** Both `nixpkgs` (25.11) and `nixpkgs-unstable` are inputs; unstable packages are accessible via the overlay or `pkgs.unstable`.
- **Theming:** Catppuccin Mocha applied globally via home-manager catppuccin module.

## Coding Style
- 2-space indentation, trailing commas in multi-line lists/attrsets, one attribute per line for large sets.
- Lowercase names with hyphens or underscores (e.g. `hardware-configuration.nix`).
- Run `just fmt` before committing.

## Commits & PRs
- Short imperative commit messages scoped to one host or module (e.g. `Add laptop NixOS profile`).
- PRs: describe what changed, list commands run (e.g. `nix flake check`), call out affected hosts.

## Verification
Before asserting file or config state, re-read it and reference the verification. If you cannot verify, say so.
