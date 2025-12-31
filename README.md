# NixOS Configs

This repository stores NixOS configurations for multiple machines using a simple, import-only layout. Hosts define machine-specific settings, modules hold shared system configuration, `users/` defines system accounts, and `home/` (when present) manages user-land configuration through Home Manager.

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
  services/
    <service>.nix
users/
  <user>.nix
home/
  <user>.nix
```

## What Each Layer Does

- **host** (`hosts/<hostname>/configuration.nix`)
  - Machine-specific system config (hardware, hostname, bootloader, host-only tweaks).
- **modules** (`modules/*.nix`)
  - Shared system modules (e.g., `modules/nix.nix` for Nix settings).
- **user** (`users/*.nix`)
  - System accounts and groups (who exists on the machine).
- **home** (`home/*.nix`)
  - Home Manager user-land packages and dotfiles.
- **services** (`modules/services/*.nix`)
  - Reusable service modules and configs.

## Example Imports

A host typically imports shared modules and user files:

```nix
{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ../../modules/nix.nix
    ../../users/<user>.nix
    ../../modules/services/<service>.nix
  ];

  # Example:
  # home-manager.users.<user> = import ../../home/<user>.nix;
}
```

## Dependency Tree

This repository follows a direct import chain where hosts are the root and everything else is pulled in from there:

```
flake.nix
└─ nixosConfigurations.<hostname>
       ├─ home-manager.nixosModules.home-manager
       └─ hosts/<hostname>/configuration.nix
            ├─ ./disko.nix
            ├─ ./hardware-configuration.nix
            ├─ modules/nix.nix
            ├─ users/<user>.nix
        ├─ modules/services/<service>.nix
        └─ home-manager.users.<user>
             └─ home/<user>.nix
```

## Build and Apply

- `nixos-rebuild switch --flake .#<hostname>`: apply config to a host.
- `nixos-rebuild build --flake .#<hostname>`: build without switching.
- `nix flake check`: evaluate flake checks.

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
- Store password hashes under `root-password` and `kra3-password`.

## Notes

- Keep configs import-only; avoid helper methods in Nix.
- Store system packages in modules or host configs; keep user packages in Home Manager.
