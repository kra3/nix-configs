# Neovim Configuration

LazyVim-based Neovim, managed declaratively with home-manager. It sits alongside Vim: `vim` stays Vim, `nvim` is Neovim, and `EDITOR`/`VISUAL` are unchanged.

> **Config Location**: `~/.config/nvim` (from `modules/home/neovim/nvim/`)
> **Module**: `modules/home/neovim/default.nix` (`home-neovim-default`, part of the dev profile)

## Overview

- **Nix supplies binaries**: `nvim` plus LSP/formatter/linter tools (`extraPackages`) are on nvim's wrapper PATH only. Mason is disabled.
- **lazy.nvim manages plugins**: LazyVim and its extras are fetched and updated by lazy.nvim at runtime.
- **Pinned by lockfile**: `modules/home/neovim/nvim/lazy-lock.json` is committed and seeded to `~/.local/state/nvim/lazy-lock.json` by a home-manager activation step (only if missing, so lazy.nvim can write to it).

## Quick Start

```bash
nvim          # first launch installs plugins
:Lazy         # plugin manager UI
:LazyExtras   # browse extras
:checkhealth  # verify tools and providers
```

## Key Bindings

The leader layout is LazyVim's (`<Space>` leader; press it and wait for which-key). Vim and IdeaVim follow the same layout where the editor can; see [Keymaps](keymaps.md). Local additions go in `modules/home/neovim/nvim/lua/config/keymaps.lua`.

## Updating Plugins

```bash
nvim          # :Lazy update
cp ~/.local/state/nvim/lazy-lock.json modules/home/neovim/nvim/lazy-lock.json
```

Commit the refreshed lockfile. Existing hosts keep their state-dir lockfile; use `:Lazy restore` to apply a newer committed one.

## Languages

Each language is a switch, `programs.neovim-langs.<lang>.enable`, set in the host or profile Home Manager config. Only enabled languages get their packages (LSP, formatter, debug adapter) and LazyVim extra.

| Lang | Default | Brings |
| --- | --- | --- |
| `nix` | on | nixd, nixfmt, statix |
| `lua` | on | lua-language-server, stylua |
| `python` | on | basedpyright, ruff |
| `typescript` | off | vtsls, biome, js-debug-adapter |
| `scala` | off | metals, bloop, JDK 21 |
| `java` | off | jdtls, JDK 21 |
| `rust` | off | rust-analyzer, codelldb |
| `go` | off | gopls, gofumpt, golangci-lint, gotools, delve |
| `cpp` | off | clang-tools, codelldb |

mac-work enables everything; sutala uses the defaults; surasa has no Neovim. Nix writes the enabled set to `lua/config/nix-langs.lua`, which `lazy.lua`, `plugins/*` and `check-tools.lua` read. Rebuild after flipping a switch; the next `nvim` start installs the new plugins.

## Adding an Extra or Plugin

- LazyVim extra: add the language to `languages` in `modules/home/neovim/default.nix` with its packages and extras.
- Own plugin: add a spec file under `lua/plugins/`.
- Tool binaries the extra needs (LSP server, formatter): add the package to that language's `packages` in `modules/home/neovim/default.nix`, since Mason is disabled.

Then run `:Lazy sync` and copy the lockfile back as above.

## Checking Tools Are Present

```bash
just nvim-check-tools
```

Lists the LSP servers, formatters and linters the enabled extras expect and flags any missing executable (exit 1 if so). Run it after enabling an extra or updating plugins. It cannot see debug adapters or other tools a plugin spawns itself, so the short `static` list at the end of `modules/home/neovim/check-tools.lua` needs extending by hand.

## Nix Language Server

`nixd` replaces LazyVim's default `nil`. In a flake it is pointed at the flake's nixpkgs and, for the NixOS and Home Manager options, at `nixosConfigurations.<hostname>` (or `darwinConfigurations.<hostname>`; falling back to the first NixOS one) so option names complete. That evaluates the flake on first use, so completions can lag the first time.

## Toolchains From The Project

`gopls` needs `go` and `rust-analyzer` needs `cargo` on PATH; they come from the project dev shell, not from this module. Java and Scala debug bundles (java-debug-adapter, java-test) are Mason-only, so Java debugging is unavailable. Offline, blink.cmp falls back to its Lua matcher until its binary downloads. On macOS, treesitter parser compilation needs the Xcode command line tools.

LSP clients stop when their last buffer closes (`config/autocmds.lua`), except `metals` and `jdtls`, which are slow to restart and run until Neovim exits.

## Related

- [Vim Configuration](vim.md)
- [Keymaps](keymaps.md)
- [Zsh Configuration](zsh.md)
- [Tmux Configuration](tmux.md)
