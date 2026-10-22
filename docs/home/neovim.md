# Neovim Configuration

LazyVim-based Neovim, managed declaratively with home-manager. Plain Vim stays as a lean fallback for root and servers.

> **Config Location**: `~/.config/nvim` (from `modules/home/neovim/nvim/`)
> **Module**: `modules/home/neovim/default.nix` (`home-neovim-default`, part of the dev profile)

## Overview

- **Nix supplies binaries**: `nvim` plus LSP/formatter/linter tools (`extraPackages`) are on nvim's wrapper PATH only. Mason is disabled.
- **lazy.nvim manages plugins**: LazyVim and its extras are fetched and updated by lazy.nvim at runtime.
- **Pinned by lockfile**: `modules/home/neovim/nvim/lazy-lock.json` is committed and seeded to `~/.local/state/nvim/lazy-lock.json` by a home-manager activation step (only if missing, so lazy.nvim can write to it).
- **Default editor**: `EDITOR`/`VISUAL` are `nvim` and `vi`/`vim` alias to `nvim` wherever the module is imported.

## Quick Start

```bash
nvim          # first launch installs plugins
:Lazy         # plugin manager UI
:LazyExtras   # browse extras
:checkhealth  # verify tools and providers
```

## Key Bindings

The leader layout is LazyVim's (`<Space>` leader; press it and wait for which-key). See the LazyVim keymap docs. Local additions go in `modules/home/neovim/nvim/lua/config/keymaps.lua`.

## Updating Plugins

```bash
nvim          # :Lazy update
cp ~/.local/state/nvim/lazy-lock.json modules/home/neovim/nvim/lazy-lock.json
```

Commit the refreshed lockfile. Existing hosts keep their state-dir lockfile; use `:Lazy restore` to apply a newer committed one.

## Adding an Extra or Plugin

- LazyVim extra: add an `{ import = "lazyvim.plugins.extras.<category>.<name>" }` line to the spec in `lua/config/lazy.lua`.
- Own plugin: add a spec file under `lua/plugins/`.
- Tool binaries the extra needs (LSP server, formatter): add the package to `extraPackages` in `modules/home/neovim/default.nix`, since Mason is disabled.

Then run `:Lazy sync` and copy the lockfile back as above.

## Lean Vim (root/servers)

`modules/home/vim/vimrc` is a plugin-free config: sane options, search/indent settings, a simple statusline, and basic mappings (`<Space>` leader, `Ctrl-hjkl` window navigation, `<leader>w` save). `.gvimrc` and `.ideavimrc` are still installed from `modules/home/vim/`.

## Related

- [Zsh Configuration](zsh.md)
- [Tmux Configuration](tmux.md)
