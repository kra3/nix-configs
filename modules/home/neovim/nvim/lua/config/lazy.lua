local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
  if vim.v.shell_error ~= 0 then
    error("Failed to clone lazy.nvim:\n" .. out)
  end
end
vim.opt.rtp:prepend(lazypath)

vim.g.lazyvim_python_lsp = "basedpyright"

local spec = {
  { "LazyVim/LazyVim", import = "lazyvim.plugins" },
  { import = "lazyvim.plugins.extras.dap.core" },
  { import = "lazyvim.plugins.extras.test.core" },
}
for _, extra in ipairs(require("config.nix-langs").extras) do
  spec[#spec + 1] = { import = "lazyvim.plugins.extras." .. extra }
end
spec[#spec + 1] = { import = "plugins" }

require("lazy").setup({
  spec = spec,
  defaults = { lazy = false, version = false },
  lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json",
  rocks = { enabled = false },
  checker = { enabled = false },
  change_detection = { notify = false },
})
