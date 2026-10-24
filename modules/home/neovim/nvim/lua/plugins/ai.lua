local model = "qwen2.5-coder:14b"

return {
  {
    "olimorris/codecompanion.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-treesitter/nvim-treesitter" },
    cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions" },
    keys = {
      { "<leader>a", group = "ai", mode = { "n", "v" } },
      { "<leader>aa", "<cmd>CodeCompanionActions<cr>", mode = { "n", "v" }, desc = "Actions" },
      { "<leader>ac", "<cmd>CodeCompanionChat Toggle<cr>", mode = { "n", "v" }, desc = "Chat" },
      { "<leader>ai", ":CodeCompanion ", mode = { "n", "v" }, desc = "Inline Prompt" },
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
