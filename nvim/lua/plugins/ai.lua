return {
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    keys = {
      { "<leader>ac", "<cmd>CodeCompanionChat Toggle<cr>", desc = "AI chat (toggle)" },
      { "<leader>aa", "<cmd>CodeCompanionActions<cr>", desc = "AI actions", mode = { "n", "v" } },
      { "<leader>ai", "<cmd>CodeCompanion<cr>", desc = "AI inline", mode = { "n", "v" } },
    },
    config = function()
      require("codecompanion").setup({
        adapters = {
          http = {
            lmstudio = function()
              return require("codecompanion.adapters").extend("openai_compatible", {
                name = "lmstudio",
                formatted_name = "LM Studio",
                env = {
                  -- LM Studio's local server (Developer tab → Start Server).
                  -- Default port is 1234; the loaded model is auto-detected
                  -- via /v1/models, so no model ID needs to be hardcoded.
                  url = "http://localhost:1234",
                  api_key = "lm-studio",
                },
              })
            end,
          },
        },
        strategies = {
          chat = { adapter = "lmstudio" },
          inline = {
            adapter = "lmstudio",
            -- Force placement so the model doesn't need to return JSON classification
            opts = { placement = "add" },
          },
        },
      })
    end,
  },
}
