local au = vim.api.nvim_create_autocmd

au("FileType", {
  pattern = "python",
  callback = function()
    vim.opt_local.colorcolumn = "88"
    vim.opt_local.textwidth = 88
  end,
})

au("FileType", {
  pattern = "markdown",
  callback = function()
    vim.opt_local.textwidth = 80
  end,
})
