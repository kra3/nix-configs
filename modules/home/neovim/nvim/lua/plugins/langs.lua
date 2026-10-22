return {
  {
    "scalameta/nvim-metals",
    ft = { "scala", "sbt" },
    opts = function(_, opts)
      opts.settings.metalsBinaryPath = vim.fn.exepath("metals")
    end,
  },
}
