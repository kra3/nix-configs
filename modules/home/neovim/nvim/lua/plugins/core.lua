local langs = require("config.nix-langs").langs

return {
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  { "jay-babu/mason-nvim-dap.nvim", enabled = false },
  { "catppuccin/nvim", name = "catppuccin", opts = { flavour = "mocha" } },
  { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin" } },
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      opts.formatters_by_ft = vim.tbl_extend("force", opts.formatters_by_ft or {}, { fish = {} })
      if not langs.lua then
        opts.formatters_by_ft.lua = {}
      end
    end,
  },
  { "mfussenegger/nvim-lint", opts = { linters_by_ft = { fish = {} } } },
  { "neovim/nvim-lspconfig", opts = { servers = { lua_ls = { enabled = langs.lua } } } },
  langs.scala and {
    "scalameta/nvim-metals",
    ft = { "scala", "sbt" },
    opts = function(_, opts)
      opts.settings.metalsBinaryPath = vim.fn.exepath("metals")
    end,
  } or nil,
}
