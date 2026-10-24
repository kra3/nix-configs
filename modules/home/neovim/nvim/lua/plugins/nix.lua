return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        nil_ls = { enabled = false },
        nixd = {
          settings = { nixd = { formatting = { command = { "nixfmt" } } } },
          on_init = function(client)
            local root = client.root_dir
            if not (root and vim.uv.fs_stat(root .. "/flake.nix")) then
              return
            end
            local flake = ('(builtins.getFlake "%s")'):format(root)
            local host = vim.uv.os_gethostname()
            local config = ('(let c = %s.nixosConfigurations; in c.${"%s"} or (builtins.head (builtins.attrValues c)))'):format(
              flake,
              host
            )
            client.settings = vim.tbl_deep_extend("force", client.settings or {}, {
              nixd = {
                nixpkgs = { expr = ("import %s.inputs.nixpkgs { }"):format(flake) },
                options = {
                  nixos = { expr = config .. ".options" },
                  home_manager = { expr = config .. ".options.home-manager.users.type.getSubOptions []" },
                },
              },
            })
            client:notify("workspace/didChangeConfiguration", { settings = client.settings })
          end,
        },
      },
    },
  },
  {
    "stevearc/conform.nvim",
    opts = { formatters_by_ft = { fish = {} } },
  },
  {
    "mfussenegger/nvim-lint",
    opts = { linters_by_ft = { fish = {} } },
  },
}
