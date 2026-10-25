local model = "qwen2.5-coder:14b"

return {
  {
    "olimorris/codecompanion.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-treesitter/nvim-treesitter" },
    cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions" },
    keys = {
      { "<leader>ao", group = "ollama", mode = { "n", "v" } },
      { "<leader>aoa", "<cmd>CodeCompanionActions<cr>", mode = { "n", "v" }, desc = "Actions" },
      { "<leader>aoc", "<cmd>CodeCompanionChat Toggle<cr>", mode = { "n", "v" }, desc = "Chat" },
      { "<leader>aoi", ":CodeCompanion ", mode = { "n", "v" }, desc = "Inline Prompt" },
    },
    opts = {
      adapters = {
        http = {
          ollama = function()
            return require("codecompanion.adapters").extend("ollama", {
              schema = { model = { default = model } },
            })
          end,
        },
      },
      interactions = {
        chat = { adapter = "ollama" },
        inline = { adapter = "ollama" },
      },
    },
  },
}
