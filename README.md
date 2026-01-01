# NixOS Configs

This repository stores NixOS configurations for multiple machines using a simple, import-only layout. Hosts define machine-specific settings, modules hold shared system configuration, and `modules/users/` defines system accounts and Home Manager user configs.

The flake is structured with `flake-parts` to keep outputs modular as the repo grows.

## Structure

```
flake.nix
hosts/
  <hostname>/
    configuration.nix
    disko.nix
    hardware-configuration.nix  # generated on the host
modules/
  nix.nix
  users/
    <user>.nix
  services/
    <service>.nix
```

## What Each Layer Does

- **host** (`hosts/<hostname>/configuration.nix`)
  - Machine-specific system config (hardware, hostname, bootloader, host-only tweaks).
- **modules** (`modules/*.nix`)
  - Shared system modules (e.g., `modules/nix.nix` for Nix settings).
- **user** (`modules/users/*.nix`)
  - System accounts and groups (who exists on the machine) plus Home Manager user-land config.
- **services** (`modules/services/*.nix`)
  - Reusable service modules and configs.

## Example Imports

A host typically imports shared modules and user files:

```nix
{ inputs, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops

    ./disko.nix
    ./hardware-configuration.nix
    ../../modules/nix.nix
    ../../modules/users/<user>.nix
    ../../modules/services/<service>.nix
  ];
}
```

`flake.nix` passes `inputs` via `specialArgs` so host configs can import `inputs.home-manager`, `inputs.disko`, and `inputs.sops-nix` directly.

## Dependency Tree

This repository follows a direct import chain where hosts are the root and everything else is pulled in from there:

```
flake.nix
└─ nixosConfigurations.<hostname>
       └─ hosts/<hostname>/configuration.nix
            ├─ inputs.home-manager.nixosModules.home-manager
            ├─ inputs.disko.nixosModules.disko
            ├─ inputs.sops-nix.nixosModules.sops
            ├─ ./disko.nix
            ├─ ./hardware-configuration.nix
            ├─ modules/nix.nix
            ├─ modules/users/<user>.nix
            ├─ modules/services/<service>.nix
            └─ home-manager.users.<user> (from modules/users/<user>.nix)
```

## Build and Apply

- `nixos-rebuild switch --flake .#<hostname>`: apply config to a host.
- `nixos-rebuild build --flake .#<hostname>`: build without switching.
- `nix flake check`: evaluate flake checks.
- `nix fmt`: format Nix files via treefmt-nix.
- `nix develop`: enter the dev shell with repo tooling.

## Just Tasks

Common operations are also available through `.justfile`:

- `just fmt`
- `just check`
- `just deploy`
- `just switch-remote`
- `just build-remote`

## Colmena Deployment

This repository exposes a `colmena` flake output for remote deployments. Update `deployment.targetHost` and `deployment.targetUser` in `flake.nix`, then run:

```
nix run github:zhaofengli/colmena -- apply --on <hostname>
```

Optional: enable the Colmena binary cache for faster builds:

```
nix run nixpkgs#cachix -- use colmena
```

## SOPS Secrets

Secrets are managed with `sops-nix`. The module is enabled via `modules/sops.nix` and derives its age key from the host SSH key.

Setup:
- On the host, derive an age recipient: `ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub`
- Add that recipient to `.sops.yaml` (replace `REPLACE_WITH_AGE_PUBLIC_KEY`)
- Encrypt `secrets/secrets.yaml` in-place once you add values.
- Store password hashes under `users.root.password` and `users.kra3.password` (literal keys).
- Store Cloudflare DNS credentials under `cloudflare.dns_api_token` (token value, literal key).
See `secrets/README.md` for the exact structure.

## Notes

- Keep configs import-only; avoid helper methods in Nix.
- Store system packages in modules or host configs; keep user packages in Home Manager.
