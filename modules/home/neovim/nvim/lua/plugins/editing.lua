return {
  { "tpope/vim-sleuth" },
  { "tpope/vim-abolish" },
  { "tpope/vim-eunuch" },
  {
    "christoomey/vim-tmux-navigator",
    cmd = { "TmuxNavigateLeft", "TmuxNavigateDown", "TmuxNavigateUp", "TmuxNavigateRight" },
    keys = {
      { "<C-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "Go to Left Window / tmux pane" },
      { "<C-j>", "<cmd>TmuxNavigateDown<cr>", desc = "Go to Lower Window / tmux pane" },
      { "<C-k>", "<cmd>TmuxNavigateUp<cr>", desc = "Go to Upper Window / tmux pane" },
      { "<C-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Go to Right Window / tmux pane" },
    },
  },
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
