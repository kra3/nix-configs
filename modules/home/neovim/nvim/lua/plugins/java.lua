local cfg = require("config.langs")

if not cfg.langs.java then
  return {}
end

local bundles = {}
for _, pattern in ipairs(cfg.bundles or {}) do
  vim.list_extend(bundles, vim.fn.glob(pattern, false, true))
end

return {
  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      opts.jdtls = vim.tbl_deep_extend("force", opts.jdtls or {}, { init_options = { bundles = bundles } })

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if not (client and client.name == "jdtls" and #bundles > 0) then
            return
          end
          local jdtls = require("jdtls")
          jdtls.setup_dap(opts.dap)
          require("jdtls.dap").setup_dap_main_class_configs(opts.dap_main)
          local map = function(lhs, fn, desc)
            vim.keymap.set("n", lhs, fn, { buffer = args.buf, desc = desc })
          end
          map("<leader>tt", require("jdtls.dap").test_class, "Run All Test")
          map("<leader>tr", require("jdtls.dap").test_nearest_method, "Run Nearest Test")
          map("<leader>tT", require("jdtls.dap").pick_test, "Run Test")
        end,
      })
    end,
  },
}
