-- AI assistant via gp.nvim — talks to Bonsai-27B (PrismML ternary quant of
-- Qwen3.6-27B), loaded like any other GGUF through LM Studio at port 1234.
-- See README.md's "Bonsai-27B" section for why this is the default over the
-- Mistral setup (capability vs. VRAM/thinking-token tradeoff) — both now run
-- through the same LM Studio server, just different model ids.
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
        -- Bonsai-27B via LM Studio — Default provider
        -- ========================================================================
        openai_api_key = "lm-studio",           -- LM Studio uses this as a placeholder
        openai_base_url = "http://localhost:1234/v1",
        openai_model_id = "bonsai-27b",

        -- ========================================================================
        -- Simple defaults — just works with Bonsai
        -- ========================================================================
        disable_stream = false,                -- See responses as they're generated
        temperature = 0.7,                     -- Balanced creativity
        max_tokens = 4096,                     -- Bonsai's hidden thinking eats into
                                                -- this budget (~190 tokens minimum,
                                                -- 2-3k for a complex request) — higher
                                                -- than Mistral's 2048 to leave room
                                                -- for an actual answer after it.

        -- ========================================================================
        -- Prompt for Bonsai — tells it to be a coding assistant
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
          -- Before sending to AI: ensure LM Studio is running
          BeforeSend = function(gp)
            local ok = pcall(vim.fn.system, { "curl", "-s", "-f", "-o", "/dev/null", "http://localhost:1234/v1/models" })
            if not ok or vim.v.shell_error ~= 0 then
              vim.notify("LM Studio may not be running. Start it first!", vim.log.levels.WARN)
            end
          end,
        },
      })
    end,
  },
}
