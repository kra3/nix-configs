return {
  {
    "tpope/vim-fugitive",
    cmd = { "Git", "G", "Gdiffsplit", "Gwrite", "Gremove", "Gedit", "Gread", "GBrowse" },
    keys = {
      { "<leader>gv", group = "fugitive" },
      { "<leader>gvs", "<cmd>Git<cr>", desc = "Status" },
      { "<leader>gvc", "<cmd>Git commit<cr>", desc = "Commit" },
      { "<leader>gvp", "<cmd>Git push<cr>", desc = "Push" },
      { "<leader>gvd", "<cmd>Gdiffsplit<cr>", desc = "Diff Split" },
      { "<leader>gvw", "<cmd>Gwrite<cr>", desc = "Write (stage)" },
      { "<leader>gvr", "<cmd>Gremove<cr>", desc = "Remove" },
    },
  },
  { "tpope/vim-rhubarb", dependencies = { "tpope/vim-fugitive" } },
}
