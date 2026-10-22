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

- Neovim (0.12.x) + **LazyVim** as the dev editor on `mac-work` and `sutala`'s `kra3` user.
- **Everything from nixpkgs** — LazyVim itself, plugins, LSPs, formatters, linters, DAP adapters,
  Treesitter grammars. No `mason`, no lazy.nvim git clones, no runtime binary downloads
  (blink.cmp's prebuilt fuzzy lib, coursier-fetched metals).
- **One upgrade channel**: `flake.lock` moves LazyVim, plugins, and tools together (see Upgrades).
- **Lazy per language** — nothing language-specific runs until a matching file opens in a project root.
- Adopt LazyVim's leader layout; realign `.ideavimrc` to it so both editors share one layout.
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
  refactor, `t` run/test, `d` debug — close to LazyVim's groups, so realigning it is small.
- `services-system-vim` (NixOS system package) is unrelated and unchanged.

## Decision 1 — Config ownership: hybrid (Nix packages + Lua config)

| Option | Verdict |
|---|---|
| **Hybrid**: Nix supplies Neovim, LazyVim, every plugin, tools, grammars; Lua config in-repo; lazy.nvim only *loads* | **Chosen** |
| nixvim / nvf (whole config as Nix options) | Rejected: Nix eval per tweak, upstream Lua docs need translating, LazyVim doesn't map onto it |
| lazy.nvim-managed plugins (`lazy-lock.json`) + Nix for binaries only | Fallback (see Upgrades): simpler wiring, but two upgrade channels |
| Imperative lazy.nvim + mason | Rejected: non-reproducible, mason binaries duplicate nixpkgs |

Mechanics:

- `programs.neovim` with `extraPackages` for every LSP/formatter/linter/DAP binary — they land on
  **nvim's wrapper PATH only**, not the login shell. Confirm whether the HM wrapper prefixes or
  suffixes PATH: suffix means a project devShell's tool version wins, which is the desired behaviour.
- Plugins from `pkgs.vimPlugins`, collected into a `linkFarm` and handed to lazy.nvim via
  `dev = { path = <linkFarm>, patterns = { "" } }`, `install.missing = false`,
  `checker.enabled = false`, `change_detection.enabled = false`, `performance.reset_packpath = false`.
  lazy.nvim keeps doing lazy-loading/keys/ft handling; Nix owns every version.
- **linkFarm entry names must equal lazy.nvim's plugin dir names** (`snacks.nvim`, `mini.ai`,
  `LazyVim`), not nixpkgs attr names (`snacks-nvim`). Derive from the drv name and keep a small
  explicit rename map for the exceptions.
- Treesitter: `vimPlugins.nvim-treesitter.withPlugins` (explicit grammar list) **or**
  `withAllGrammars` — parsers *and* queries both from Nix so they never drift. Override LazyVim's
  treesitter spec: `opts.ensure_installed = {}`, no `build`, no `auto_install`.
- Lua lives under `modules/home/neovim/nvim/` and is linked to `~/.config/nvim` with
  `config.lib.file.mkOutOfStoreSymlink` to the checkout, so edits are live without `just switch`.
  (A store-copied fallback is fine for `sutala` if the checkout path isn't stable there.)

## Decision 2 — Distro: LazyVim

| Option | Verdict |
|---|---|
| **LazyVim + Extras** | **Chosen.** Strong defaults; per-language Extras cover the whole language list; leader groups already close to `.ideavimrc` |
| Own config, kickstart-shaped | Not chosen: full control of keymaps, but every language and UI piece is hand-wired |
| AstroNvim / NvChad | Not pursued — extra abstraction layer / UI-first with thin language support |

LazyVim-on-Nix specifics:

- `vimPlugins.LazyVim` (16.0.1 at `6c29584`) is loaded like any other plugin from the linkFarm.
- **Disable mason** — `{ "mason-org/mason.nvim", enabled = false }` and
  `{ "mason-org/mason-lspconfig.nvim", enabled = false }`; servers resolve from PATH. Set
  `mason = false` on any server an Extra would otherwise try to install.
- **Extras are enabled in code**, as `{ import = "lazyvim.plugins.extras.lang.<x>" }` in
  `lua/config/lazy.lua`, not via `:LazyExtras` (which writes `lazyvim.json`). One reviewable list.
- **Every plugin an enabled Extra pulls in must be in the linkFarm** — with `install.missing = false`
  a missing one errors at startup. The Nix plugin list is maintained alongside the Extras list.
- Theme: LazyVim defaults to tokyonight; override to `catppuccin-nvim` (Mocha, matches host theming)
  and keep tokyonight in the linkFarm or disable its spec.

## Plugin set

LazyVim core defaults (all present in pinned nixpkgs `6c29584`): `lazy-nvim`, `LazyVim`,
`snacks-nvim` (picker, explorer, dashboard, bufdelete, lazygit), `blink-cmp` + `friendly-snippets`,
`conform-nvim`, `nvim-lint`, `nvim-lspconfig`, `nvim-treesitter` + `-textobjects` + `nvim-ts-autotag`,
`gitsigns-nvim`, `flash-nvim`, `which-key-nvim`, `trouble-nvim`, `todo-comments-nvim`, `grug-far-nvim`,
`noice-nvim` + `nui-nvim`, `lualine-nvim`, `bufferline-nvim`, `mini-ai`, `mini-pairs`, `mini-icons`,
`ts-comments-nvim`, `persistence-nvim`, `lazydev-nvim`, `plenary-nvim`.

What they replace from the vimrc: vim-plug → lazy.nvim; asyncomplete/vsnip → blink; fzf.vim,
NERDTree, bbye/bufonly → snacks; ALE → conform + nvim-lint; signify → gitsigns; sneak → flash;
vim-which-key → which-key; airline → lualine; auto-pairs → mini.pairs; regex syntax plugins →
Treesitter.

Added on top: `vim-tmux-navigator`, `vim-fugitive` + rhubarb, abolish, eunuch, undotree, vimwiki,
sleuth, `catppuccin-nvim`, `codecompanion-nvim` (Ollama adapter, matches current vim-ai use).
Dropped (built into Neovim ≥0.10/0.11): vim-commentary (`gc`), most of vim-unimpaired, highlightedyank.

## Language stack

All binaries and plugins verified present at nixpkgs `6c29584`.

| Lang | LazyVim Extra | LSP | Format / lint | DAP | Test | Notes |
|---|---|---|---|---|---|---|
| Scala | `lang.scala` | `metals` 1.6.9 (+ `bloop`) | `scalafmt` via metals | via metals | metals | `nvim-metals`; set `metalsBinaryPath` to Nix metals |
| Java | `lang.java` | `jdt-language-server` 1.61 | via jdtls | jdtls bundles | jdtls | `nvim-jdtls` |
| Python | `lang.python` | `basedpyright` 1.39 | `ruff` 0.16 | `python3Packages.debugpy` | `neotest-python` | `venv-selector-nvim`; direnv |
| TS/JS | `lang.typescript` (+ `linting.eslint` / `formatting.prettier` or `formatting.biome`) | `vtsls` 0.3 | `biome` 2.5, or `eslint_d` + `prettierd` | `vscode-js-debug` | `neotest-vitest` | — |
| Rust | `lang.rust` | `rust-analyzer` | rustfmt, clippy | `vscode-extensions.vadimcn.vscode-lldb` | rustaceanvim | `rustaceanvim`, `crates-nvim` |
| Go | `lang.go` | `gopls` 0.23 | `gofumpt`, `golangci-lint` 2.14 | `delve` | `neotest-golang` | `nvim-dap-go` |
| C/C++ | `lang.clangd` | `clangd` (`clang-tools` 21) | clang-format, clang-tidy | codelldb / `lldb` | — | `clangd_extensions-nvim`; needs `compile_commands.json`; `--query-driver` for Apple clang |
| Nix, Lua | `lang.nix` | `nixd`, `lua-language-server` | `nixfmt` | — | — | editing this repo / the nvim config |

Cross-cutting Extras: `dap.core`, `test.core`, `ai.*` as chosen.

JVM: one JDK (`temurin-bin-21`) on nvim's PATH for metals/jdtls; avoids `jdk_headless` source builds
on aarch64-darwin. Project JDKs come from devShells.

## Lazy activation

- **LSP**: a server starts on matching `FileType` **and** a root marker (`build.sbt`, `pom.xml`,
  `pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`, `compile_commands.json`). One process per
  (server, root).
- nvim-metals / rustaceanvim / nvim-jdtls attach from ftplugin/FileType autocmds; LazyVim Extras
  already lazy-load their plugins by `ft`.
- DAP adapters spawn only on a debug session; conform / nvim-lint run short-lived processes on save /
  edit (except `eslint_d`, `prettierd` daemons).
- Add an `LspDetach` autocmd that stops a client once no buffers remain attached — servers otherwise
  live until nvim exits.
- `bloop` outlives nvim: configure metals/bloop shutdown or document `bloop exit`.

## Upgrades

With everything from nixpkgs, there is **one upgrade path**: `just update` → PR → `just switch`.

| Component | Upgraded by | Notes |
|---|---|---|
| Neovim | `flake.lock` | — |
| LazyVim | `flake.lock` (`vimPlugins.LazyVim`) | Majors arrive via `just update`; read LazyVim's NEWS/CHANGELOG on a major bump |
| Plugins | `flake.lock` (`vimPlugins.*`) | lazy.nvim's updater is inert (`install.missing=false`, `checker` off); `:Lazy update` does nothing useful; no `lazy-lock.json` |
| LSPs, formatters, linters, DAP | `flake.lock` (`extraPackages`) | Same lock as plugins, so plugin ↔ server API pairs move together |
| Treesitter grammars + queries | `flake.lock` (`nvim-treesitter.withPlugins`) | Always matched |
| Project-specific tool versions | the project's devShell | Wins over the nvim-wrapper copy if PATH is suffixed |

Consequences:

- **Atomic + rollbackable**: a bad bump is undone by switching to the previous generation or reverting
  `flake.lock`. No half-updated plugin dir.
- **Lag**: nixpkgs `vimPlugins` trail upstream by days–weeks. Source `vimPlugins` (and fast-moving
  servers) from `pkgs.unstable` rather than the stable channel to keep LazyVim and its plugins
  close to the versions LazyVim's specs target.
- **Version skew risk**: LazyVim's specs can assume a plugin API newer than nixpkgs ships (or vice
  versa). Mitigation: every `just update` PR runs the headless health checks below; on breakage, pin
  the one plugin with `vimUtils.buildVimPlugin` + `fetchFromGitHub` until nixpkgs catches up.
- **Adding an Extra = two edits**: the `import` line in Lua and the plugin(s) in the Nix list.

Fallback if the Nix plugin wiring proves too costly: let lazy.nvim manage plugins with a committed
`lazy-lock.json` (`:Lazy update` + commit), keep Nix for Neovim, binaries, grammars, and build-step
plugins (`blink-cmp`). That gives two upgrade channels and network fetches at first start, in exchange
for zero name-mapping and always-current LazyVim.

## Keymap migration

Adopt LazyVim's default layout; override only a short list. Non-leader keys carry over: `<Space>`
leader, `<C-hjkl>` (tmux-navigator), `<C-s>`, `j/k`→`gj/gk`, visual `< >` reselect, `[d ]d [e ]e`,
`gd gD K`.

vimrc keys that change under LazyVim defaults:

| vimrc today | LazyVim |
|---|---|
| `<leader><leader>` sneak | find files (flash moves to `s`) |
| `<leader>/` Files | grep |
| `<leader>b` Buffers | buffer group (`<leader>,` / `<leader>fb` lists) |
| `<leader>w` `:w!` | window group (`<C-s>` saves) |
| `<leader>n` NERDTree | notifications (`<leader>e` explorer) |
| `<leader>f` format, `ft/fm/fh` | find group; format `<leader>cf` |
| `<leader>u` undotree | UI-toggle group |
| `<leader>t*` tabs | `<leader><tab>*`; `t` = test |
| `<leader>cd` cd-to-file | line diagnostics |
| `<leader>rn` rename | `<leader>cr` (and built-in `grn`) |
| `<leader>s*` spelling/subst/signify | search group; hunks `]h [h <leader>gh*` |
| `gt` type-def | `gy` |
| visual `J/K` move | `<A-j>/<A-k>` |
| `ys/cs/ds` surround | mini.surround `gsa/gsd/gsr` — or swap in `nvim-surround` to keep tpope keys |

Decide in PR 3: whether to keep `;`→`:` (collides with flash `f`/`t` repeat), tpope-style surround,
and a home for undotree (e.g. `<leader>U`).

Custom vimscript (`ToggleWindowLayout`, `[m ]m` method jumps, `RenameFile`, `FixWhitespace`,
`SudoSave`, Java helpers): port to Lua in `lua/config/` or source as a `.vim` file; prefer LazyVim /
Treesitter equivalents where they exist (`]f [f`, `snacks.rename`).

`.ideavimrc` is realigned to the LazyVim layout in the same PR as the keymap port.

## Module layout (dendritic naming)

| File | Registers | Imported by |
|---|---|---|
| `modules/home/neovim/default.nix` | `home-neovim-default` | `home-profiles-dev` |
| `modules/home/neovim/nvim/**` | — (LazyVim starter tree, linked to `~/.config/nvim`) | — |
| `modules/home/vim/default.nix` | `home-vim-default` (unchanged name, trimmed to a lean vimrc) | `home-profiles-core` |

Lua tree follows the LazyVim starter: `init.lua`, `lua/config/{lazy,options,keymaps,autocmds}.lua`,
`lua/plugins/*.lua` (overrides: mason off, treesitter, theme, extra plugins).

`shell/common`: `EDITOR`/`VISUAL` → `nvim` only where `home-neovim-default` is imported (set it in
that module with `mkDefault`/override rather than changing `shell/common`'s value for root).

Docs: replace `docs/home/vim.md` with `docs/home/neovim.md` (+ a short note on the lean vim).

## Extension points for downstream configs

Downstream configs (e.g. the work overlay) must be able to add machine-local pieces without forking,
same as the existing `aerospace` and `sketchybar/local.sh` hooks:

1. **Plain home-manager option merging** — downstream appends to `programs.neovim.extraPackages`
   and to the plugin list feeding the linkFarm; both are lists and merge.
2. **`local` hook in a separate dir** — `~/.config/nvim` is a live symlink into this checkout, so
   downstream must **not** write under it (files would land in this repo's working tree). Instead
   `init.lua` adds `~/.config/nvim-local` to `runtimepath` (via lazy.nvim `performance.rtp.paths`,
   since lazy resets rtp) and does `pcall(require, "local")` last; downstream writes
   `xdg.configFile."nvim-local/lua/local/..."`.
3. **lazy.nvim spec import** — `spec` imports `lazyvim.plugins`, the Extras, `plugins`, plus
   `local.plugins` only when that module exists on the runtimepath, so downstream can add/override
   plugin specs and Extras.

All language tooling in this spec (including Scala/Java) stays here; downstream adds only
machine-local settings.

## Rollout

1. **PR 1 — scaffold**: `home-neovim-default` with Neovim, LazyVim core + its default plugins in the
   linkFarm, mason off, Treesitter from Nix, theme, `lang.nix` + `lang.python`. Added to
   `home-profiles-dev`. Vim untouched; `EDITOR` still vim.
2. **PR 2 — languages**: remaining Extras (Scala, Java, TS/JS, Rust, Go, C/C++), `dap.core`,
   `test.core`, their plugins and binaries.
3. **PR 3 — keymaps + ideavim**: the few overrides, custom function ports, `.ideavimrc` realignment.
4. **PR 4 — cutover**: `EDITOR=nvim` for dev profile, `vi`/`vim` aliases, lean `vimrc`, docs swap.

Each PR: `just fmt`, `nix flake check`, `just build mac-work` and `just build sutala`.

## Verification (per PR and per `just update`)

- `nvim --headless "+checkhealth" +qa` — no errors for lazy, lazyvim, lsp, treesitter, blink.
- `:checkhealth lazy` / `:Lazy` — no plugin "not installed" with `install.missing = false`.
- No network on startup: first launch after `just switch` creates no new dirs under
  `~/.local/share/nvim/lazy`.
- Open one file per language in a sample project: `:checkhealth vim.lsp` lists exactly that server;
  opening nothing → zero LSP processes (`pgrep -fl 'metals|rust-analyzer|gopls|vtsls|clangd'`).
- Startup: `nvim --startuptime` < ~80 ms with no file.
- Root user on `sutala`: `which nvim` empty, `vim` still works.

## Risks

- **LazyVim ↔ nixpkgs plugin version skew** → health checks on every `just update`; pin a single
  plugin when needed; `vimPlugins` from unstable.
- **linkFarm name mapping** and missing Extra plugins → land the wiring in PR 1 with health checks
  before adding languages.
- **LazyVim default churn** (picker/completion swaps between majors) → majors only arrive via
  reviewed `just update` PRs; read NEWS.
- **Grammar/query drift** if any Treesitter piece comes from outside Nix → keep both from Nix.
- **Darwin clangd/SDK headers** → `--query-driver`, document `compile_commands.json` generation.
- **Metals memory / bloop residency** on the laptop → shutdown config, LspDetach stop.

## Open questions

- Biome vs eslint+prettier as the TS default (per-project config usually decides).
- Explicit grammar list vs `withAllGrammars` (closure size vs convenience).
- Should `sutala`'s `kra3` get the full language set, or a lighter subset?
- Keep tpope surround keys (`nvim-surround`) or adopt mini.surround's `gs*`?
