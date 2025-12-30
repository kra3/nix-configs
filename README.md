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

## Notes

- Keep configs import-only; avoid helper methods in Nix.
- Store system packages in modules or host configs; keep user packages in Home Manager.
