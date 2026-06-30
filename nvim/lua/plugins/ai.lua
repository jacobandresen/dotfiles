return {
  {
    "Robitx/gp.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    keys = {
      { "<leader>ac", "<cmd>GpChatToggle<cr>", desc = "AI chat (toggle)" },
      { "<leader>aa", "<cmd>GpChatNew<cr>", desc = "AI new chat", mode = { "n", "v" } },
      { "<leader>ai", "<cmd>'<,'>GpChatPaste<cr>", desc = "AI inline", mode = { "n", "v" } },
    },
    config = function()
      local gp = require("gp")
      
      gp.setup({
        -- LM Studio OpenAI-compatible API
        openai_api_key = "lm-studio",
        openai_base_url = "http://localhost:1234/v1",
        
        -- Default to auto-detect model from /v1/models
        openai_model_id = "auto",
        
        -- Disable default keymaps (we use our own)
        chat_shortcut = false,
        
        -- Custom system prompt for Mistral AI
        system_prompt = "You are a helpful AI coding assistant. " ..
                       "You write concise, correct code. " ..
                       "You help with debugging, explaining, and optimizing code. " ..
                       "When asked to write code, provide the complete implementation. " ..
                       "Use the programming language and style from the current file.",
        
        -- Streaming enabled
        disable_stream = false,
        temperature = 0.7,
        max_tokens = 4096,
      })
    end,
  },
}
