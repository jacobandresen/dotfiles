-- AI assistant via gp.nvim — simple, direct, works with local Mistral models in LM Studio
return {
  {
    "Robitx/gp.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      -- Chat: toggle with <leader>ac
      { "<leader>ac", "<cmd>GpChatToggle<cr>", desc = "Toggle AI chat" },
      -- New chat in various contexts
      { "<leader>an", "<cmd>GpChatNew<cr>", desc = "New AI chat" },
      { "<leader>ap", "<cmd>GpChatPaste<cr>", desc = "Paste into AI chat", mode = { "n", "v" } },
      -- Inline: replace selection or line with AI
      { "<leader>ai", "<cmd>'<,'>GpChatPaste<cr>", desc = "Replace with AI", mode = { "n", "v" } },
      -- Quick actions
      { "<leader>ae", "<cmd>GpExplain<cr>", desc = "Explain code", mode = { "n", "v" } },
      { "<leader>ar", "<cmd>GpRewrite<cr>", desc = "Rewrite code", mode = { "n", "v" } },
    },
    config = function()
      require("gp").setup({
        -- ========================================================================
        -- LM Studio (local Mistral models) — Zero config required!
        -- ========================================================================
        openai_api_key = "lm-studio",           -- LM Studio uses this as a placeholder
        openai_base_url = "http://localhost:1234/v1",
        openai_model_id = "auto",              -- Auto-detects your loaded model
        
        -- ========================================================================
        -- Simple defaults — just works with Mistral
        -- ========================================================================
        disable_stream = false,                -- See responses as they're generated
        temperature = 0.7,                     -- Balanced creativity
        max_tokens = 2048,                     -- Good for most coding tasks
        
        -- ========================================================================
        -- Prompt for Mistral AI — tells it to be a coding assistant
        -- ========================================================================
        system_prompt = "You are Mistral, a helpful AI coding assistant. " ..
                       "Write clean, correct, well-commented code. " ..
                       "Explain your reasoning. Use the same language and style as the current file.",
        
        -- ========================================================================
        -- Disable default keymaps (we define our own above)
        -- ========================================================================
        chat_shortcut = false,
        
        -- ========================================================================
        -- Optional: Custom commands for common tasks
        -- ========================================================================
        hooks = {
          -- Before sending to AI: ensure LM Studio is running
          BeforeSend = function(gp)
            -- Check if we can reach LM Studio
            local ok, _ = pcall(vim.fn.readfile, "http://localhost:1234/v1/models")
            if not ok then
              vim.notify("LM Studio may not be running. Start it first!", vim.log.levels.WARN)
            end
          end,
        },
      })
    end,
  },
}
