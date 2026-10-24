-- Run via `just nvim-check-tools`: lists every tool the enabled LazyVim extras expect and flags missing executables.
local results = {}

local function need(kind, source, exe)
  if not exe or exe == "" then
    return
  end
  results[#results + 1] = { ok = vim.fn.executable(exe) == 1, kind = kind, source = source, exe = exe }
end

require("lazy").load({ plugins = { "nvim-lspconfig", "conform.nvim", "nvim-lint" } })

-- servers whose plugin starts them itself instead of through vim.lsp.config
local langs_cfg = require("config.langs")
local langs = langs_cfg.langs
local plugin_started = {}
local plugin_servers = {
  java = { "jdtls", "jdtls" },
  scala = { "metals", "metals" },
  rust = { "rust_analyzer", "rust-analyzer" },
}
for lang, server in pairs(plugin_servers) do
  if langs[lang] then
    plugin_started[server[1]] = server[2]
  end
end

for name, sopts in pairs(LazyVim.opts("nvim-lspconfig").servers or {}) do
  if sopts ~= false and (type(sopts) ~= "table" or sopts.enabled ~= false) then
    local cmd = vim.lsp.config[name] and vim.lsp.config[name].cmd
    need("lsp", name, plugin_started[name] or (type(cmd) == "table" and cmd[1]) or nil)
  end
end
for name, exe in pairs(plugin_started) do
  need("lsp", name .. " (plugin)", exe)
end

local conform = require("conform")
for ft, formatters in pairs(conform.formatters_by_ft) do
  if type(formatters) == "table" then
    for _, name in ipairs(formatters) do
      if type(name) == "string" then
        local ok, info = pcall(conform.get_formatter_info, name)
        if ok and info and info.command and info.command ~= "" then
          need("format", ft .. ":" .. name, info.command)
        end
      end
    end
  end
end

local lint = require("lint")
for ft, names in pairs(lint.linters_by_ft) do
  for _, name in ipairs(names) do
    local ok, linter = pcall(function()
      local l = lint.linters[name]
      return type(l) == "function" and l() or l
    end)
    if ok and type(linter) == "table" then
      local cmd = linter.cmd
      if type(cmd) == "function" then
        cmd = cmd()
      end
      need("lint", ft .. ":" .. name, cmd)
    end
  end
end

-- not discoverable from plugin specs; extend when enabling an extra that needs more
for _, exe in ipairs(vim.list_extend({ "git", "rg", "fd", "tree-sitter", "cc" }, langs_cfg.tools)) do
  need("static", "baseline", exe)
end

table.sort(results, function(a, b)
  return a.kind .. a.exe < b.kind .. b.exe
end)
local seen, missing = {}, 0
for _, r in ipairs(results) do
  local key = r.kind .. r.exe
  if not seen[key] then
    seen[key] = true
    missing = missing + (r.ok and 0 or 1)
    io.stdout:write(("%-8s %-8s %-28s %s\n"):format(r.ok and "ok" or "MISSING", r.kind, r.exe, r.source))
  end
end
io.stdout:write(("\n%d missing\n"):format(missing))
vim.cmd(missing > 0 and "cquit 1" or "qa")
