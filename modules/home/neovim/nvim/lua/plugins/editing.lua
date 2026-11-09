return {
  { "tpope/vim-abolish" },
  {
    "christoomey/vim-tmux-navigator",
    cmd = { "TmuxNavigateLeft", "TmuxNavigateDown", "TmuxNavigateUp", "TmuxNavigateRight" },
    -- after/plugin/herdr_nav.lua owns <C-h/j/k/l> and calls TmuxNavigate* inside tmux.
    init = function()
      vim.g.tmux_navigator_no_mappings = 1
    end,
  },
}
