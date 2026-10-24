return {
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  { "jay-babu/mason-nvim-dap.nvim", enabled = false },
  { "catppuccin/nvim", name = "catppuccin", opts = { flavour = "mocha" } },
  { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin" } },
  {
    "scalameta/nvim-metals",
    ft = { "scala", "sbt" },
    opts = function(_, opts)
      opts.settings.metalsBinaryPath = vim.fn.exepath("metals")
    end,
  },
}
