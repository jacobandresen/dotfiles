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
            -- <leader>ai: small context, capped output, no thinking, kept
            -- resident longer. Chat keeps the unrestricted "ollama" adapter.
            ollama_fast = function()
              return require("codecompanion.adapters").extend("ollama", {
                schema = {
                  model = { default = ollama_model() },
                  num_ctx = { default = 2048 },
                  think = { default = false },
                  keep_alive = { default = "30m" },
                  num_predict = {
                    order = 13,
                    mapping = "parameters.options",
                    type = "number",
                    optional = true,
                    default = 512,
                    desc = "Cap response length for fast inline edits.",
                  },
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
              -- Copilot Chat's "+" attach-context button: fuzzy list of
              -- every context type and slash command, no # / syntax to recall.
              add_context = {
                modes = { n = "<C-g>", i = "<C-g>" },
                callback = function(chat) require("codecompanion.interactions.chat.action_palette").launch(chat) end,
                description = "Add context",
                index = 1,
              },
            },
          },
          inline = { adapter = "ollama_fast" },
        },
      })

      -- <leader>ai edits silently in the background with no streaming
      -- buffer to watch (unlike chat) - show a fidget spinner instead.
      -- One inline edit can fire more than one underlying HTTP request
      -- (e.g. a placement/classification pass before the content one), so
      -- track an in-flight count rather than pairing by request id - and
      -- auto-clear after 60s so a missed/failed finish can't wedge it open.
      local inline_count = 0
      local inline_handle = nil
      local inline_timer = nil
      local function inline_stop()
        inline_count = 0
        if inline_timer then
          inline_timer:stop()
          inline_timer:close()
          inline_timer = nil
        end
        if inline_handle then
          inline_handle:finish()
          inline_handle = nil
        end
      end
      vim.api.nvim_create_autocmd("User", {
        pattern = "CodeCompanionInlineStarted",
        callback = function()
          inline_count = inline_count + 1
          if not inline_handle then
            inline_handle = require("fidget.progress").handle.create({
              title = "Inline edit",
              message = "Thinking...",
              lsp_client = { name = "CodeCompanion" },
            })
            inline_timer = vim.uv.new_timer()
            inline_timer:start(60000, 0, vim.schedule_wrap(inline_stop))
          end
        end,
      })
      vim.api.nvim_create_autocmd("User", {
        pattern = "CodeCompanionRequestFinished",
        callback = function(args)
          if inline_count == 0 or args.data.interaction ~= "inline" then
            return
          end
          inline_count = inline_count - 1
          if inline_count == 0 then
            inline_stop()
          end
        end,
      })
    end,
  },

  {
    -- Copilot-style ghost-text via local Ollama. Chat-completions (not FIM)
    -- so it works with any loaded model, not just FIM-trained coder models -
    -- see openai_compatible vs openai_fim_compatible in the plugin's README.
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
