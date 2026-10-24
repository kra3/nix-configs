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

local keep_running = { metals = true, jdtls = true }

au("LspDetach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client or keep_running[client.name] then
      return
    end
    vim.schedule(function()
      if not client:is_stopped() and next(client.attached_buffers) == nil then
        client:stop()
      end
    end)
  end,
})
