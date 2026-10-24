return {
  { "tpope/vim-sleuth" },
  { "tpope/vim-abolish" },
  { "tpope/vim-eunuch" },
  {
    "mbbill/undotree",
    cmd = "UndotreeToggle",
    keys = { { "<leader>U", "<cmd>UndotreeToggle<cr>", desc = "Undotree" } },
    init = function()
      vim.g.undotree_SetFocusWhenToggle = 1
      vim.g.undotree_ShortIndicators = 1
    end,
  },
  {
    "vimwiki/vimwiki",
    init = function()
      vim.g.vimwiki_list = { { path = "~/.vimwiki/", syntax = "markdown", ext = ".md" } }
      vim.g.vimwiki_global_ext = 0
      vim.g.vimwiki_map_prefix = "<leader>W"
    end,
  },
}
