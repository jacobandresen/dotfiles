-- AI assistant via CodeCompanion.nvim, switchable between Ollama (whichever
-- model is currently loaded) and GitHub Copilot with `ga` inside the chat buffer.
-- Inline ghost-text suggestions (Minuet, further below) follow the same model.
local ollama_model = require("util.ollama").current_model

return {
  {
    -- Not used for inline ghost-text (disabled below) - installed purely so
    -- `:Copilot auth` can produce the OAuth token CodeCompanion's copilot
    -- adapter reads. Run `:Copilot auth` once after install.
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    opts = {
      suggestion = { enabled = false },
      panel = { enabled = false },
    },
  },
  {
    "olimorris/codecompanion.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ac", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle AI chat", mode = { "n", "v" } },
      { "<leader>an", "<cmd>CodeCompanionChat<cr>", desc = "New AI chat" },
      { "<leader>ap", "<cmd>CodeCompanionChat Add<cr>", desc = "Add selection to AI chat", mode = "v" },
      { "<leader>ai", "<cmd>CodeCompanion<cr>", desc = "Inline AI edit", mode = { "n", "v" } },
      -- Explain/fix/tests/etc. live in the action palette (ships built in,
      -- no custom hooks needed the way gp.nvim required for GpExplain).
      { "<leader>aa", "<cmd>CodeCompanionActions<cr>", desc = "AI actions", mode = { "n", "v" } },
    },
    config = function()
      require("codecompanion").setup({
        adapters = {
          http = {
            ollama = function()
              return require("codecompanion.adapters").extend("ollama", {
                schema = {
                  model = { default = ollama_model() },
                },
              })
            end,
            copilot = "copilot",
          },
        },
        interactions = {
          chat = {
            adapter = "ollama",
            -- narrower, sidebar-like panel, closer to VS Code's Copilot Chat
            window = { width = 0.35 },
            keymaps = {
              -- Copilot Chat's "+" attach-context button: one key, fuzzy list
              -- of every context type (#buffer, #selection, #diagnostics...)
              -- and slash command (/file, /symbols...) instead of memorising
              -- the `#`/`/` syntax.
              add_context = {
                modes = { n = "<C-g>", i = "<C-g>" },
                callback = function(chat) require("codecompanion.interactions.chat.action_palette").launch(chat) end,
                description = "Add context",
                index = 1,
              },
            },
          },
          inline = { adapter = "ollama" },
        },
      })
    end,
  },

  {
    -- Copilot-style ghost-text suggestions, powered by the local Ollama model.
    -- Uses the chat-completions endpoint (not FIM) so it works with whichever
    -- general instruct model happens to be loaded, not just FIM-trained
    -- coder models - see the "openai_compatible" vs "openai_fim_compatible"
    -- trade-off in the plugin's README.
    "milanglacier/minuet-ai.nvim",
    event = "InsertEnter",
    config = function()
      require("minuet").setup({
        provider = "openai_compatible",
        n_completions = 1, -- resource saving for a local model
        context_window = 512, -- small + fast; raise if completions feel too shallow
        request_timeout = 10, -- local inference can be slower than a cloud API
        throttle = 2000, -- avoid hammering the local server while typing
        debounce = 800,
        provider_options = {
          openai_compatible = {
            name = "Ollama",
            end_point = "http://localhost:11434/v1/chat/completions",
            api_key = function() return "ollama" end, -- unused, but required to be non-nil
            model = ollama_model(),
            optional = {
              max_tokens = 128,
              think = false, -- skip reasoning preamble on hybrid-thinking models
            },
          },
        },
        virtualtext = {
          auto_trigger_ft = {
            "c", "cpp", "rust", "cs", "javascript", "typescript",
            "javascriptreact", "typescriptreact", "lua", "python", "go",
            "sh", "yaml", "json",
          },
          keymap = {
            accept = "<A-A>",
            accept_line = "<A-a>",
            accept_n_lines = "<A-z>",
            prev = "<A-[>",
            next = "<A-]>",
            dismiss = "<A-e>",
          },
        },
      })
    end,
  },
}
