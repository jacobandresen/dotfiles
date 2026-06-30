return {
  {
    "niba/continue.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    keys = {
      { "<leader>ac", "<cmd>Continue<cr>", desc = "AI chat (toggle)" },
      { "<leader>aa", "<cmd>ContinueActions<cr>", desc = "AI actions", mode = { "n", "v" } },
      { "<leader>ai", "<cmd>ContinueInline<cr>", desc = "AI inline", mode = { "n", "v" } },
    },
    config = function()
      require("continue").setup({
        providers = {
          lmstudio = {
            name = "LM Studio",
            apiKey = "lm-studio",
            baseUrl = "http://localhost:1234/v1",
            model = nil,  -- Auto-detect from /v1/models
          },
        },
        -- Default to LM Studio provider
        defaultProvider = "lmstudio",
        -- Enable chat and inline completion
        enableChat = true,
        enableInline = true,
        -- Auto-complete on <Tab> in chat
        enableTabCompletion = true,
        -- Show thought process
        showThinking = true,
        -- Maximum tokens to generate
        maxTokens = 4096,
        -- Temperature
        temperature = 0.7,
        -- Send code context automatically
        sendCode = true,
        -- Send file context automatically
        sendFiles = true,
        -- Number of messages to keep in history
        historyLength = 50,
        -- Custom system prompt for Mistral AI models
        systemPrompt = function()
          return "You are a helpful AI coding assistant. " ..
                 "You write concise, correct code. " ..
                 "You help with debugging, explaining, and optimizing code. " ..
                 "When asked to write code, provide the complete implementation. " ..
                 "Use the programming language and style from the current file."
        end,
      })
    end,
  },
}
