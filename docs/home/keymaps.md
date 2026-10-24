# Keymaps: Vim, Neovim, IdeaVim

All three editors follow LazyVim's key layout (`<Space>` leader). Where an editor cannot do something (LSP and Snacks pickers in plain Vim), the key is skipped rather than faked. "Old" is the state before this change.

See also: [Vim](vim.md), [Neovim](neovim.md).

## Vim

### Moved or changed

| Old key | New key | Action | Note |
|---------|---------|--------|------|
| `;` | (removed) | `;` -> `:` | Conflicted with sneak/flash f/t repeat |
| `<leader>w` | `<C-s>` (kept) | Save | `<leader>w` is now the window group |
| `<leader><CR>` | `<Esc>`, `<leader>ur` | Clear search highlight | |
| `j` / `k` | `j` / `k` | Display-line motion | Now only without a count, as in LazyVim |
| `J` / `K` (visual) | `<A-j>` / `<A-k>` | Move selected lines | Normal and insert mode too |
| `<leader>ba` | `<leader>bo` | Close other buffers | via vim-bufonly |
| `<leader>b` | `<leader>fb`, `<leader>,` | Buffer list (fzf) | |
| `<leader>h/j/k/l` | `<C-h/j/k/l>` | Window navigation | vim-tmux-navigator |
| `<C-Arrows>` | `<C-Arrows>` | Was window navigation, now resize | |
| `<leader>+` `<leader>-` `<leader>>` `<leader><` | `<C-Arrows>` | Resize | |
| `<leader>-` | `<leader>-` | Split below | Was resize |
| (none) | `<leader>\|` | Split right | |
| `<leader>we` | (removed) | Equalize windows | Use `<C-w>=` |
| `<leader>tn` `to` `tc` `tl` `th` | `<leader><Tab><Tab>` `o` `d` `l` `]` `[` `f` | New / only / close / last / next / prev / first tab | `<leader>te`, `<leader>tm`, `<leader>1`-`9`, `<leader>0` removed |
| `<leader>tt` | `<leader>ft` | Terminal | `t` is the test group |
| `<leader>/` | `<leader><Space>`, `<leader>ff` | Files (fzf) | `<leader>/` is now grep |
| `<leader>ft` | `<leader>ss` | Tags (fzf) | |
| `<leader>fm` | `<leader>sm` | Marks | |
| `<leader>fh` | `<leader>fr` | Recent files | |
| `<leader>sc` | `<leader>sw` | Grep word under cursor | `<leader>sc` is now command history |
| `<leader>ss` | (removed) | `:SudoSave` | Command remains; `ss` is now Tags |
| `<leader>sj` `sk` | `]h` `[h` | Next / previous hunk | signify |
| `<leader>sd` `su` | `<leader>ghp` `<leader>ghr` | Hunk diff / undo | |
| `<leader>sh` | (removed) | Toggle signify highlight | `sh` is now help tags |
| `<leader>st` | `<leader>uG` | Toggle signify | |
| `<leader>u` | `<leader>U` | Undotree | Same as Neovim |
| `<leader>n` `nf` | `<leader>e` `E` (also `fe` `fE`) | NERDTree toggle / find file | |
| `<leader>gb` `gd` `gl` | unchanged | Blame / diff split / log | |
| `<leader>gs` | `<leader>gs`, `<leader>gg` | Git status | |
| `<leader>gc` | `<leader>gvc` | Git commit | `gc` is now commit browser (`:Commits`) |
| `<leader>gp` `gw` `gr` | `<leader>gvp` `gvw` `gvr` | Push / write / remove | `gv` is the fugitive group, same as Neovim |
| `<leader>fw` | `<leader>cw` | Trim trailing whitespace | Same as Neovim |
| `<leader>rf` | `<leader>cR` | Rename file | |
| `<leader>cd` | (removed) | cd to file dir | Use `:cd %:p:h` or vim-rooter |
| `<leader>fb` (python) | `<leader>cf` (python) | Format with ruff/black | |
| `<leader>w{w,t,d,r,s}` (vimwiki) | `<leader>W{w,t,d,r,s}` | Vimwiki maps | `g:vimwiki_map_prefix`, same as Neovim |
| `<leader><leader>` `<leader>S` | `s` / `S` | Sneak forward / backward | Like flash.nvim; `s` no longer substitutes |
| vim-commentary `gc` | built-in `gc` / `gcc` | Comment | Same keys |

### New

| Key | Action |
|-----|--------|
| `<leader>qq` | Quit all |
| `<leader>bb`, `` <leader>` `` | Alternate buffer |
| `<leader>bd` / `<leader>bD` | Delete buffer (keep window) / `:bdelete` |
| `[b` `]b` | Previous / next buffer (unimpaired) |
| `<leader>ww` `wd` `w-` `w\|` `wt` | Other window / close / split below / split right / toggle layout |
| `<leader>fg` `fr` `fe` | Git files / recent / explorer |
| `<leader>,` | Buffers |
| `<leader>sg` `sw` `sb` `sk` `sh` `sC` `sc` `:` | Grep / word / buffer lines / keymaps / help tags / commands / command history |
| `<leader>gf` `gB` | File history / open on GitHub |
| `<leader>ur` | Redraw and clear highlight |
| `<leader>us` `uw` `ul` `uL` | Toggle spell / wrap / number / relativenumber |
| `<leader>xq` `xl` | Open quickfix / location list |
| `gco` `gcO` | Comment line below / above |
| `<C-s>` (visual), undo breakpoints on `,` `.` `;`, `n`/`N` always forward/back with `zv` | LazyVim parity |

### Removed with their plugins

LSP maps (`gd` `gD` `gr` `gi` `gt` `K` hover, `<leader>rn` `ca` `cl` `ds` `ws` `dd` `f`, `[d` `]d`), ALE (`[e` `]e`, `<leader>at` `af` `ad`), vsnip (`<C-j>` `<C-l>` `<C-h>` in insert/select), asyncomplete (`<Tab>` `<S-Tab>` `<CR>` popup handling), vim-ai (`<leader>a*`), and Metals maps for Scala.

### Plugins removed / kept / swapped

- Removed: vim-lsp, vim-lsp-settings, asyncomplete, asyncomplete-lsp, vim-vsnip, vim-vsnip-integ, friendly-snippets, ALE, vim-scala, python-syntax, vim-javascript, yats.vim, emmet-vim, vim-ai
- Swapped: vim-commentary -> built-in `comment` package (`packadd! comment`)
- Kept: fzf, fzf.vim, nerdtree (+ git plugin), vim-rooter, vim-sneak, fugitive, signify, rhubarb, surround, repeat, abolish, unimpaired, auto-pairs, peekaboo, undotree, indent-object, bufonly, bbye, tmux-navigator, airline (+ themes), catppuccin, sleuth, highlightedyank, which-key, vimwiki, eunuch, obsession
- Nix: `basedpyright` dropped from `home-vim-default` packages; `ruff` stays for the `<leader>cf` python map

## Neovim

Neovim is LazyVim, so only local additions and local deviations are listed. Old = LazyVim defaults (these were not bound before).

| Old key | New key | Action | Note |
|---------|---------|--------|------|
| (none) | `<leader>cw` | Trim trailing whitespace | Also `:FixWhitespace` |
| (none) | `<leader>wt` | Toggle window layout | Same as Vim |
| (none) | `<leader>gv{s,c,p,d,w,r}` | Fugitive status / commit / push / diff / write / remove | vim-fugitive, lazy-loaded |
| (none) | `<leader>U` | Undotree | |
| (none) | `<leader>W*` | Vimwiki maps | `vimwiki_map_prefix`, so `<leader>w` stays windows |
| (none) | `<leader>a{a,c,i}` | CodeCompanion actions / chat / inline | Ollama `qwen2.5-coder:14b` |

Plugins added: vim-sleuth, vim-abolish, vim-eunuch, undotree, vimwiki, vim-fugitive, vim-rhubarb, codecompanion.nvim. LazyVim keys are not overridden (`<C-h/j/k/l>` stay plain window moves; tmux pane crossing is Vim-only). Settings: `colorcolumn=120`; python `88`; markdown `textwidth=80`.

## IdeaVim

| Old key | New key | Action | Note |
|---------|---------|--------|------|
| `<leader>h/j/k/l` | `<C-h/j/k/l>` | Window navigation | |
| `<leader>wv` `ws` | `<leader>\|` `-` (also `w\|` `w-`) | Split right / below | |
| `<leader>tn` `tp` `tc` `tC` `to` `tr` `tP` | `<leader><Tab>` `]` `[` `d` `D` `o` `r` `p` | Tab ops | |
| `<leader>tt` / `td` / `tD` / `tR` | `<leader>tt` run class, `<leader>dd` / `dD` debug | Test and debug | `tt` was terminal; terminal is `<leader>ft` |
| `<leader>sf` | `<leader>/`, `<leader>sg` | Find in path | |
| `<leader>/` | `<leader>ss` | File structure | |
| `<leader>n` `nf` | `<leader>e` `E` (also `fe` `fE`) | Project view / select in view | |
| `<leader>f` `o` | `<leader>cf` `co` | Reformat / optimize imports | |
| `<leader>cd` `ce` | `<leader>cd` | Error description | Javadoc stays on `K` |
| `gD` | `gy` | Type declaration | `gD` is declaration |
| `gt` | `<leader>tg` | Go to test | |
| `[m` `]m` | `[f` `]f` | Method up / down | |
| `<leader>z` | `<leader>uz` | Distraction free mode | |
| `<leader><CR>` | `<Esc>`, `<leader>ur` | Clear search highlight | |
| `n` `N` (centered) | `n` `N` | Plain search motion | `zz` removed to match Vim/Neovim |
| `J` `K` (visual) | `<A-j>` `<A-k>` | Move lines | IDE move-line action |
| `<leader>gc` | `<leader>gvc` | Commit dialog | `gc` is now log, as in LazyVim |
| `<leader>gp` `gu` | `<leader>gvp` `gvu` | Push / update project | |
| `<leader>gv` | `<leader>gg` | VCS popup | |
| `<leader>gD` `gh` | `<leader>gf` | File history | |
| `<leader>gr` | `<leader>ghr` | Roll back changed lines | |
| `<leader>fe` | `<leader>fe` | Was recent locations, now project view | |

New: `j`/`k` -> `gj`/`gk`, `<leader>qq` quit all, `<leader>bb`, `` <leader>` `` alternate file, `<leader>bd` close tab, `<leader>bo` close others, `[b` `]b`, `<leader>ww`, `<leader>wd`, `<leader>fb` and `<leader>,` switcher, `<leader><Space>` files, `<leader>ft` terminal, `<leader>gg`, `<leader>gf`.
