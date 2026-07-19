-- AI assistant via gp.nvim — talks to Qwen3-8b-aqua, loaded like
-- any other GGUF through LM Studio at port 1234. Chosen as the default over
-- Bonsai-27B: Bonsai's ternary Q1_0 quant only dequantizes correctly on
-- llama.cpp's CPU/CUDA backends, not Vulkan (used for Intel/AMD iGPUs like
-- this host's Arc), so it's CPU-bound here (~2.4 tok/s, 5+ min prompt-eval
-- stalls). Qwen3-8b-aqua's standard quant offloads fine to Vulkan and loads/
-- answers in seconds — see README.md's "GPU offload: CUDA works, Vulkan
-- doesn't" section. Both models run through the same LM Studio server, just
-- different model ids.
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
        -- Qwen3-8b-aqua via LM Studio — Default provider
        -- ========================================================================
        openai_api_key = "lm-studio",           -- LM Studio uses this as a placeholder
        openai_base_url = "http://localhost:1234/v1",
        openai_model_id = "qwen3-8b-aqua",

        -- ========================================================================
        -- Simple defaults — just works with Qwen3-8b-aqua
        -- ========================================================================
        disable_stream = false,                -- See responses as they're generated
        temperature = 0.7,                     -- Balanced creativity
        max_tokens = 4096,                     -- Room for a full code response

        -- ========================================================================
        -- Prompt for Qwen3-8b-aqua — tells it to be a coding assistant
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
