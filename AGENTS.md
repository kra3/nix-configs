# Repository Guidelines

## Project Structure & Module Organization
This repository holds NixOS configurations for multiple machines. Keep host-specific configs separated and shared logic centralized. Use simple, direct imports (no helper methods) for composition. The expected layout is:
- `flake.nix` and `flake.lock` for inputs and system outputs.
- `hosts/<hostname>/configuration.nix` for each machine (current host: `hosts/sutala/` for an `x86_64-linux` server).
- `hosts/<hostname>/disko.nix` for disk layout (using `/dev/disk/by-id/` paths).
- `modules/nix.nix` for shared Nix settings (flakes and `nix-command`).
- `modules/services/<service>.nix` for reusable service modules and configs.
- `users/<user>.nix` for system users (primary user: `kra3`; `root` is implicit).
- `home/<user>.nix` for Home Manager configs.
Nix build outputs (`result`, `result-*`) and `direnv` artifacts (`.direnv/`) are ignored and should not be committed.

## Host Roles & Home Manager
Servers install software via `environment.systemPackages` and system services. Home Manager is used for user services and user-land configuration (e.g., `home/kra3.nix`), enabled via the flake input and imported into the host config. Keep user-specific packages and dotfiles in `home/`, and keep system-level changes in `modules/` or host files.

## Build, Test, and Development Commands
Use host-targeted commands so changes are explicit and reproducible. Common examples (adjust to match the repo’s structure):
- `nixos-rebuild switch --flake .#<hostname>`: apply the config to a machine.
- `nixos-rebuild build --flake .#<hostname>`: build the system without switching.
- `nix flake check`: evaluate and run checks defined by the flake.
- `nix develop`: enter a dev shell if one is provided.
If you are not using flakes, document the equivalent `nixos-rebuild -I` or `nix-build` commands here.

## Coding Style & Naming Conventions
Keep Nix files readable and consistent: 2-space indentation, trailing commas in multi-line lists/attrsets, and one attribute per line for large sets. Use descriptive, lowercase names with hyphens or underscores (e.g., `hardware-configuration.nix`, `users.nix`). If a formatter is configured (e.g., `nix fmt`), run it before committing.

## Testing Guidelines
Treat `nix flake check` as the primary validation step for evaluation and checks. If you add host-specific checks or test derivations, document how to run them and what outputs to expect.

## Commit & Pull Request Guidelines
Use short, imperative commit messages (e.g., "Add laptop NixOS profile") and keep changes scoped to one host or module. For pull requests, include a clear description, list any commands run (e.g., `nix flake check`), and call out affected hosts.

## Configuration & Secrets
Avoid committing secrets or machine-specific credentials. If you adopt secret management (e.g., `sops-nix` with age keys), document key setup and file locations here. Keep local-only overrides out of version control.
