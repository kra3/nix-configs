# Vim Configuration

Vim 9 with vim-plug for general editing. Coding and IDE work (LSP, completion, linting, snippets) lives in Neovim; see [Neovim Configuration](neovim.md).

> **Config**: `modules/home/vim/vimrc` (installed via `programs.vim`), also used by root
> **Module**: `modules/home/vim/default.nix` (`home-vim-default`), also installs `~/.vim/autoload/plug.vim`, `~/.gvimrc`, `~/.ideavimrc`
> **Keys**: layout follows LazyVim in Vim, Neovim and IdeaVim; see [Keymaps](keymaps.md)

`vim` stays Vim and `nvim` is Neovim; `EDITOR`/`VISUAL` remain `vim`.

## Quick Start

```bash
vim +PlugInstall +qall   # install plugins into ~/.vim/plugged
vim +HealthCheck         # versions, tools, plugin status
```

## Plugins

Managed by vim-plug (`call plug#begin('~/.vim/plugged')` at the top of the vimrc). Plugins are not provided by Nix.

| Area | Plugins |
|------|---------|
| Search / files | fzf, fzf.vim, nerdtree (+ git plugin), vim-rooter, vim-sneak |
| Git | vim-fugitive, vim-signify, vim-rhubarb |
| Editing | vim-surround, vim-repeat, vim-abolish, vim-unimpaired, auto-pairs, vim-peekaboo, undotree, vim-indent-object, vim-sleuth, vim-highlightedyank |
| Windows / buffers | vim-bufonly, vim-bbye, vim-tmux-navigator |
| UI | vim-airline (+ themes), catppuccin |
| Utilities | vim-which-key, vimwiki, vim-eunuch, vim-obsession |

Comments use Vim's built-in `comment` package (`packadd! comment`, Vim 9.1.0375+): `gc{motion}`, `gcc`, plus `gco`/`gcO` mapped in the vimrc.

### Removed

vim-lsp, vim-lsp-settings, asyncomplete (+ lsp source), vim-vsnip (+ integ), friendly-snippets, ALE, vim-scala, python-syntax, vim-javascript, yats.vim, emmet-vim, vim-ai, and vim-commentary (replaced by the built-in package). basedpyright was dropped from the Vim home packages; ruff stays for the python format map.

## Key Bindings

Leader is `<Space>`; press it to see which-key. The full old-to-new table is in [Keymaps](keymaps.md). Highlights:

- Find: `<Space><Space>` files, `<leader>/` grep, `<leader>,` buffers, `<leader>fr` recent
- Buffers `<leader>b*`, windows `<leader>w*`, tabs `<leader><Tab>*`, git `<leader>g*`
- `<C-s>` save, `<Esc>` clears search highlight, `<A-j>`/`<A-k>` move lines
- `s`/`S` are vim-sneak (like flash.nvim in LazyVim); `;` and `,` repeat `f`/`t`/`s`

## Custom Commands

`:Touch`, `:RenameFile`, `:SudoSave`, `:FixWhitespace`, `:ReplaceAll`, `:ProjectReplace`, `:ToggleWindowLayout`, `:SaveSession`, `:LoadSession`, `:HealthCheck`, `:GenerateLocalConfig`.

## Local Overrides

`~/.vimrc.local` and per-project `.vim.local` / `.lvimrc` are sourced if present.

## Related Documentation

- [Neovim Configuration](neovim.md) - LazyVim-based Neovim for coding
- [Keymaps](keymaps.md) - Vim, Neovim and IdeaVim key changes
- [Tmux Configuration](tmux.md) - Terminal multiplexer (works great with vim-tmux-navigator)
- [Git Configuration](git.md) - Git tools that integrate with vim-fugitive
- [Bash Configuration](bash.md) - Shell configuration (sources vimwiki integration via `n` command)
- [Zsh Configuration](zsh.md) - Shell configuration (sources vimwiki integration via `n` command)
