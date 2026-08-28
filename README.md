# NixOS Configs

NixOS and macOS configurations managed with Nix flakes. Hosts define machine-specific settings; shared modules cover system services, dotfiles, and Home Manager user config.

## Hosts

| Host | OS | Role |
|------|----|------|
| `sutala` | NixOS (x86_64-linux) | Home server — media, home-automation, monitoring |
| `mac-work` | macOS (aarch64-darwin) | Personal laptop — nix-darwin + Home Manager |

## Structure

```
flake.nix
hosts/
  sutala/            # NixOS host
  mac-work/          # nix-darwin host
modules/
  home/              # Home Manager dotfiles (shared across hosts/users)
    shell/           # bash, zsh, readline, common env vars & aliases
    git/             # git, delta, lazygit
    vim/             # vim config
    tmux.nix         # tmux with catppuccin + plugins
    fzf.nix          # fzf with fd
    bat.nix          # bat (cat replacement)
    eza.nix          # eza (ls replacement)
    gh/              # GitHub CLI
    gpg.nix          # GPG + SSH agent
    packages.nix     # user packages
    ...
  services/          # NixOS system services (nginx, postgres, containers, …)
  containers/        # Podman quadlet container stacks
  users/             # System accounts + Home Manager entrypoints
```

## Home Manager Options

`modules/home/` is a flat set of leaf modules (git, vim, tmux, fzf, …) with no
shared aggregator or `dotfiles.*` options — each host's `imports` list picks
which leaves it wants (see `hosts/sutala/home.nix`, `hosts/mac-work/default.nix`).

Work-specific settings (a `~/.gitconfig.work` include, credential-file
exclusions for ripgrep) live in `modules/home/work.nix` and are opt-in: a host
imports it to enable them (`mac-work` does, `sutala` doesn't).

## Dotfiles

All dotfiles are managed declaratively via Home Manager:

- **Shell** — bash and zsh configured via `programs.bash`/`programs.zsh`; shared env vars, PATH, and aliases in `shell/common/`; readline in `programs.readline`
- **Theme** — [Catppuccin Mocha](https://github.com/catppuccin/nix) applied globally via `catppuccin.enable = true`; individual overrides per tool
- **LS_COLORS** — managed by `catppuccin.vivid` (sets `programs.vivid.activeTheme`)
- **Machine-local config** — place in `~/.shell_local` (not tracked in git); sourced at end of every shell session

## Build and Apply

**NixOS (sutala):**
```bash
nixos-rebuild switch --flake .#sutala
# Remote deploy:
just deploy          # colmena apply
just switch-remote   # nixos-rebuild over SSH
```

**macOS (nix-darwin):**
```bash
darwin-rebuild switch --flake .#mac-work
```

**Checks and formatting:**
```bash
nix flake check
nix fmt              # treefmt-nix
nix develop          # dev shell with repo tooling
```

## Secrets

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix). The age key is derived from the host SSH key.

```bash
# On host: get age recipient
ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub

# Add recipient to .sops.yaml, then edit secrets
sops secrets/secrets.yaml
```

See `secrets/README.md` for the full secrets layout.

## Adding a New Machine

1. Create `hosts/<hostname>/configuration.nix` (NixOS) or `hosts/<hostname>/darwin-configuration.nix` (macOS)
2. Add an entry for the host to `flake/hosts.nix` (one table, one definition per host — `flake.nix` turns it into `nixosConfigurations`, `darwinConfigurations`, and `colmena` entries)
3. Import `modules/users/kra3.nix` (or create a new user module) to bring in Home Manager dotfiles
4. For NixOS: run `nixos-generate-config` on the host to produce `hardware-configuration.nix` and `disko.nix`

## Notes

- Modules self-register into a flat flake-parts registry (see CLAUDE.md for the naming convention); helper functions live in `modules/lib/` and are consumed via `flakeLib`
- System packages go in host configs or service modules; user packages go in `modules/home/packages.nix`
- Container stacks live in `modules/containers/` as Podman quadlets
