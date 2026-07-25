-- AI assistant via gp.nvim — talks to gemma4:12b via Ollama at port 11434.
-- gemma4:12b is the unified model for all platforms, running through Ollama.
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
        -- gemma4:12b via Ollama — Default provider
        -- ========================================================================
        openai_api_key = "not-needed",           -- Ollama doesn't need an API key
        openai_base_url = "http://localhost:11434/v1",
        openai_model_id = "gemma4:12b",

        -- ========================================================================
        -- Simple defaults — just works with gemma4:12b
        -- ========================================================================
        disable_stream = false,                -- See responses as they're generated
        temperature = 0.7,                     -- Balanced creativity
        max_tokens = 4096,                     -- Room for a full code response

        -- ========================================================================
        -- Prompt for gemma4:12b — tells it to be a coding assistant
        -- ========================================================================
        system_prompt = "You are a helpful AI coding assistant. " ..
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
          -- Before sending to AI: ensure Ollama is running
          BeforeSend = function(gp)
            local ok = pcall(vim.fn.system, { "curl", "-s", "-f", "-o", "/dev/null", "http://localhost:11434/v1/models" })
            if not ok or vim.v.shell_error ~= 0 then
              vim.notify("Ollama may not be running. Start it first!", vim.log.levels.WARN)
            end
          end,
        },
      })
    end,
  },
}
