local au = vim.api.nvim_create_autocmd

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
