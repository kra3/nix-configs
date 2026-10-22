# Neovim Migration — home-manager dev editor

Status: **proposal** — no code in this PR. Implementation lands in follow-up PRs.

## Problem

`modules/home/vim/` (`home-vim-default`) ships a 1667-line Vim 9 `vimrc` with ~45 vim-plug plugins and
~133 mappings. Plugins are fetched imperatively by vim-plug at runtime; only `basedpyright` and `ruff`
come from Nix. The language stack is built on Vim-era plumbing — `vim-lsp` + `vim-lsp-settings`
(auto-downloads servers), `asyncomplete`, `vim-vsnip`, ALE, regex syntax plugins — that the Neovim
ecosystem has replaced with built-in LSP, Treesitter, and faster completion.

Goal: a modern Neovim dev setup for Scala, Java, Python, TS/JS, Rust, Go, C/C++, with every
binary supplied by Nix, while keeping plain Vim for root/servers.

## Goals

- Neovim (0.12.x, `vim.lsp.config`/`vim.lsp.enable`, new Treesitter API) as the dev editor on
  `mac-work` and `sutala`'s `kra3` user.
- **All tooling from nixpkgs** — LSPs, formatters, linters, DAP adapters, Treesitter grammars. No
  `mason`, no runtime binary downloads (`vim-lsp-settings`, blink.cmp's prebuilt fuzzy lib,
  coursier-fetched metals).
- **Lazy per language** — nothing language-specific runs until a matching file opens in a project root.
- Keep the user's leader-key system recognisable; converge it with `.ideavimrc` so both editors share
  one layout.
- Documented extension points so downstream configs can add machine-local bits without forking.

## Non-goals

- Removing Vim. `home-vim-default` stays (lean) for `users-root`, SSH sessions, and as a fallback.
- Replacing IntelliJ for heavy Scala/Java refactoring; Neovim covers day-to-day editing.
- Per-project compiler/runtime versions — those stay in each project's devShell via direnv.

## Constraints found in the current tree

- `users-root` imports `home-profiles-core`, which imports `home-vim-default`. **Neovim and its
  language servers must not go into `core`**, or root gets the full dev toolchain.
- `home-profiles-dev` (git, gh, uv) is imported by `mac-work` and `sutala` only — the natural home.
- `shell/common` sets `EDITOR = "vim"` and aliases `vi = "vim"`.
- `tmux.nix` already sets `@resurrect-strategy-nvim 'session'`.
- `.ideavimrc` already diverges from `vimrc` and uses grouped leaders — `f` find, `c` code, `r`
  refactor, `t` run/test, `d` debug. Those groups largely match modern Neovim conventions, so the
  new layout should converge on them rather than on the `vimrc`'s flat leaders.
- `services-system-vim` (NixOS system package) is unrelated and unchanged.

## Decision 1 — Config ownership: hybrid (Nix tools + Lua config)

| Option | Verdict |
|---|---|
| **Hybrid**: Nix supplies Neovim, tools, grammars, build-step plugins; Lua config in-repo; `lazy.nvim` loads plugins | **Chosen** |
| nixvim / nvf (whole config as Nix options) | Rejected: Nix eval per tweak, upstream Lua docs need translating, option coverage lags plugins |
| Imperative lazy.nvim + mason | Rejected: non-reproducible, mason binaries duplicate nixpkgs |

Mechanics:

- `programs.neovim` with `extraPackages` for every LSP/formatter/linter/DAP binary — they land on
  **nvim's wrapper PATH only**, not the login shell.
- Plugins from `pkgs.vimPlugins`, exposed to lazy.nvim via `dev.path` pointing at a `linkFarm` of
  those plugins, `install.missing = false`, `performance.reset_packpath = false`. lazy.nvim keeps doing
  lazy-loading/keys/ft handling; Nix owns the plugin versions.
- Treesitter: `vimPlugins.nvim-treesitter.withPlugins` (explicit grammar list) **or**
  `withAllGrammars` — parsers *and* queries both from Nix so they never drift. No `ensure_installed` /
  `auto_install`.
- Lua lives under `modules/home/neovim/nvim/` and is linked to `~/.config/nvim` with
  `config.lib.file.mkOutOfStoreSymlink` to the checkout, so edits are live without `just switch`.
  (A store-copied fallback is fine for `sutala` if the checkout path isn't stable there.)

## Decision 2 — Distro vs own config

| Option | Fit |
|---|---|
| **Own config, kickstart-shaped** (lazy.nvim + chosen plugins) | **Recommended.** Full control of the leader layout; no fighting distro defaults; small enough to read end to end |
| LazyVim + Extras | Viable alternative: its leader groups already resemble `.ideavimrc`; per-language Extras save setup. Costs: frequent default churn, mason must be disabled per server, Extras assume LazyVim's keymap namespace |
| AstroNvim / NvChad | Not pursued — extra abstraction layer / UI-first with thin language support |

Open for the implementer to confirm; the rest of this spec holds for either.

## Plugin set (all present in pinned nixpkgs `6c29584`)

| Role | Plugin | Replaces |
|---|---|---|
| Loader | `lazy-nvim` | vim-plug |
| Completion + snippets | `blink-cmp` (+ friendly-snippets) | asyncomplete, vim-vsnip |
| Picker, explorer, misc | `snacks-nvim` | fzf.vim, NERDTree, bbye/bufonly |
| Format / lint | `conform-nvim` / `nvim-lint` | ALE |
| Git | `gitsigns-nvim` + `vim-fugitive` (kept) | vim-signify |
| Motion | `flash-nvim` | vim-sneak |
| Keymap hints | `which-key-nvim` | vim-which-key |
| Syntax | `nvim-treesitter` | vim-scala, python-syntax, vim-javascript, yats |
| Debug / test | `nvim-dap` (+ view/ui) / `neotest` | — |
| Tmux | `vim-tmux-navigator` (kept) | — |
| Theme | `catppuccin-nvim` (Mocha, matches host theming) | catppuccin/vim |
| AI | `codecompanion-nvim` (Ollama adapter, matches current vim-ai use) | vim-ai |

Kept as-is (work in Neovim): fugitive, rhubarb, abolish, eunuch, undotree, vimwiki, sleuth.
Dropped (built into Neovim ≥0.10/0.11): vim-commentary (`gc`), most of vim-unimpaired (`[q ]q [b ]b`
…), vim-highlightedyank (`vim.hl.on_yank`).

## Language stack

All binaries verified present at nixpkgs `6c29584`.

| Lang | LSP | Format / lint | DAP | Test | Integration |
|---|---|---|---|---|---|
| Scala | `metals` 1.6.9 (+ `bloop`) | `scalafmt` via metals | via metals | metals test explorer | `nvim-metals` (not lspconfig); set `metalsBinaryPath` to Nix metals |
| Java | `jdt-language-server` 1.61 | via jdtls | via jdtls bundles | jdtls | `nvim-jdtls` from ftplugin |
| Python | `basedpyright` 1.39 | `ruff` 0.16 (LSP) | `python3Packages.debugpy` | `neotest-python` | venv detection via direnv / venv-selector |
| TS/JS | `vtsls` 0.3 | `biome` 2.5, or `eslint_d` + `prettierd` | `vscode-js-debug` | `neotest-vitest`/`-jest` | — |
| Rust | `rust-analyzer` | rustfmt, clippy via r-a | `vscode-extensions.vadimcn.vscode-lldb` (codelldb) | rustaceanvim | `rustaceanvim` (not lspconfig) |
| Go | `gopls` 0.23 | `gofumpt`, `golangci-lint` 2.14 | `delve` | `neotest-golang` | `nvim-dap-go` |
| C/C++ | `clangd` (`clang-tools` 21) | clang-format, clang-tidy via clangd | codelldb / `lldb` | — | needs `compile_commands.json`; `--query-driver` for Apple clang on darwin |
| Nix, Lua | `nixd`, `lua-language-server` | `nixfmt` | — | — | editing this repo / the nvim config itself |

JVM: one JDK (`temurin-bin-21`) on nvim's PATH for metals/jdtls; avoids `jdk_headless` source builds
on aarch64-darwin. Project JDKs come from devShells.

## Lazy activation

- **LSP**: `vim.lsp.enable(...)` only registers; a server starts on matching `FileType` **and** a
  root marker (`build.sbt`, `pom.xml`, `pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`,
  `compile_commands.json`). One process per (server, root).
- nvim-metals / rustaceanvim / nvim-jdtls attach from ftplugin/FileType autocmds.
- Language plugins are `ft`-lazy in lazy.nvim; DAP adapters spawn only on a debug session; conform /
  nvim-lint run short-lived processes on save / edit (except `eslint_d`, `prettierd` daemons).
- Add an `LspDetach` autocmd that stops a client once no buffers remain attached — servers otherwise
  live until nvim exits.
- `bloop` outlives nvim: configure metals/bloop shutdown or document `bloop exit`.

## Keymap migration

Non-leader keys carry over: `<Space>` leader, `<C-hjkl>` (tmux-navigator), `<C-s>`, `j/k`→`gj/gk`,
visual `< >` reselect, visual `J/K` move, `[d ]d`, `gd gD K`.

Leader layout converges on the `.ideavimrc` groups:

| Group | Contents | Current vimrc keys that move |
|---|---|---|
| `f` find | files, buffers, grep, recent, symbols | `<leader>/`, `<leader>b`, `<leader>ft/fm/fh` |
| `c` code | action, format, diagnostics, rename | `<leader>ca` (same), `<leader>f` → `cf`, `<leader>rn` → `cr` (and built-in `grn`) |
| `r` refactor | rename/extract where LSP supports | aligns with ideavim `r*` |
| `g` git | fugitive + gitsigns hunks | signify `<leader>s{j,k,d,u,h,t}` → `]h [h <leader>gh*` |
| `t` test/run | neotest | tabs move to `<leader><tab>*` |
| `d` debug | nvim-dap | `<leader>d`/`dd` diagnostics move to `c` |
| `a` AI | codecompanion | same prefix as vim-ai today |
| `s` search/replace | substitute, spelling | keep user's `<leader>sr/ss/sc` |

Decide during implementation: `<leader><leader>` (sneak today → flash `s`), `<leader>w` (`:w!` today),
`;`→`:` (conflicts with flash `f`/`t` repeat), `gt` (type-def today; Neovim tab-next) → `gy`, tpope
surround `ys/cs/ds` (keep via `nvim-surround` or remap `mini.surround`).

Custom vimscript (`ToggleWindowLayout`, `[m ]m` method jumps, `RenameFile`, `FixWhitespace`,
`SudoSave`, Java helpers): port to Lua or source as a `.vim` file; replace `[m ]m` with Treesitter
textobjects where it's cleaner.

`.ideavimrc` gets the matching edits in the same PR as the keymap port.

## Module layout (dendritic naming)

| File | Registers | Imported by |
|---|---|---|
| `modules/home/neovim/default.nix` | `home-neovim-default` | `home-profiles-dev` |
| `modules/home/neovim/nvim/**` | — (Lua tree, linked to `~/.config/nvim`) | — |
| `modules/home/vim/default.nix` | `home-vim-default` (unchanged name, trimmed to a lean vimrc) | `home-profiles-core` |

`shell/common`: `EDITOR`/`VISUAL` → `nvim` only where `home-neovim-default` is imported (set it in
that module with `mkDefault`/override rather than changing `shell/common`'s value for root).

Docs: replace `docs/home/vim.md` with `docs/home/neovim.md` (+ a short note on the lean vim).

## Extension points for downstream configs

Downstream configs (e.g. the work overlay) must be able to add machine-local pieces without forking,
same as the existing `aerospace` and `sketchybar/local.sh` hooks:

1. **Plain home-manager option merging** — downstream appends to `programs.neovim.extraPackages`
   and `programs.neovim.plugins`; both are lists and merge.
2. **`local` hook in a separate dir** — `~/.config/nvim` is a live symlink into this checkout, so
   downstream must **not** write under it (files would land in this repo's working tree). Instead
   `init.lua` adds `~/.config/nvim-local` to `runtimepath` (via lazy.nvim `performance.rtp.paths`,
   since lazy resets rtp) and does `pcall(require, "local")` last; downstream writes
   `xdg.configFile."nvim-local/lua/local/..."`.
3. **lazy.nvim spec import** — `spec` imports `plugins`, plus `local.plugins` only when that module
   exists on the runtimepath, so downstream can add/override plugin specs.

All language tooling in this spec (including Scala/Java) stays here; downstream adds only
machine-local settings.

## Rollout

1. **PR 1 — scaffold**: `home-neovim-default` with Neovim, plugin linkFarm, Treesitter, LSP for
   Python + Nix + Lua, picker, completion, git, theme, keymap core. Added to `home-profiles-dev`.
   Vim untouched; `EDITOR` still vim.
2. **PR 2 — languages**: Scala, Java, TS/JS, Rust, Go, C/C++ + DAP + neotest + format/lint.
3. **PR 3 — keymaps + ideavim**: full leader layout, custom function ports, `.ideavimrc` alignment.
4. **PR 4 — cutover**: `EDITOR=nvim` for dev profile, `vi`/`vim` aliases, lean `vimrc`, docs swap.

Each PR: `just fmt`, `nix flake check`, `just build mac-work` and `just build sutala`.

## Verification (per PR)

- `nvim --headless "+checkhealth" +qa` — no errors for lsp, treesitter, lazy, blink.
- `:checkhealth lazy` reports no missing plugins with `install.missing = false`.
- Open one file per language in a sample project: `:checkhealth vim.lsp` lists exactly that server;
  opening nothing → zero LSP processes (`pgrep -fl 'metals|rust-analyzer|gopls|vtsls|clangd'`).
- Startup: `nvim --startuptime` < ~80 ms with no file.
- Root user on `sutala`: `which nvim` empty, `vim` still works.

## Risks

- **Grammar/query drift** if any Treesitter piece comes from outside Nix → keep both from Nix.
- **lazy.nvim + Nix plugin wiring** (packpath reset, `dev.path`) is the fiddliest part → land in PR 1
  with health checks before adding languages.
- **Darwin clangd/SDK headers** → `--query-driver`, document `compile_commands.json` generation.
- **Metals memory / bloop residency** on the laptop → shutdown config, LspDetach stop.
- **Plugin options drift** across nixpkgs bumps → `just update` PRs run the headless health check.

## Open questions

- Own config vs LazyVim (Decision 2) — recommendation: own config.
- Biome vs eslint+prettier as the TS default (per-project config usually decides).
- Explicit grammar list vs `withAllGrammars` (closure size vs convenience).
- Should `sutala`'s `kra3` get the full language set, or a lighter subset?
