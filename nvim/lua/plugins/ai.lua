-- AI assistant via CodeCompanion.nvim, switchable between Ollama (whichever
-- model is currently loaded) and GitHub Copilot with `ga` inside the chat buffer.
-- Inline ghost-text suggestions (Minuet, further below) follow the same model.
local ollama = require("util.ollama")
local ollama_model = ollama.current_model
local tuning = require("util.ollama_tuning").current()
local copilot_configured = require("util.copilot").is_configured()
local copilot_model = "gpt-5.6-luna"
local copilot_reasoning_effort = "low"

local codecompanion_keys = {
  { "<leader>cw", function() require("util.ai_wand").fix() end, desc = "Magic wand: fix diagnostic" },
  { "<leader>ac", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle AI chat", mode = { "n", "v" } },
  { "<leader>an", "<cmd>CodeCompanionChat<cr>", desc = "New AI chat" },
  { "<leader>ap", function() require("util.ai_chat").add(false) end, desc = "Add file to AI chat" },
  { "<leader>ap", function() require("util.ai_chat").add(true) end, desc = "Add selection to AI chat", mode = "x" },
  { "<leader>ab", function() require("util.ai_chat").back() end, desc = "Back to code" },
  { "<leader>ai", "<cmd>CodeCompanion<cr>", desc = "Inline AI edit", mode = { "n", "v" } },
  { "<leader>aa", "<cmd>CodeCompanionActions<cr>", desc = "AI actions", mode = { "n", "v" } },
  { "<leader>as", function() require("codecompanion").sessions() end, desc = "Saved AI chats" },
  { "<leader>ae", function() require("codecompanion").changes() end, desc = "Files the AI edited (quickfix)" },
}
if copilot_configured then
  codecompanion_keys[#codecompanion_keys + 1] = {
    "<leader>aP",
    function() require("codecompanion").chat({ params = { adapter = "copilot" } }) end,
    desc = "New Copilot chat",
  }
  codecompanion_keys[#codecompanion_keys + 1] = {
    "<leader>aA",
    function()
      local chat = require("codecompanion").last_chat()
      if not chat then
        return vim.notify("No chat open", vim.log.levels.WARN)
      end
      require("codecompanion.interactions.chat.keymaps.change_adapter").callback(chat)
    end,
    desc = "Change AI chat adapter",
  }
  codecompanion_keys[#codecompanion_keys + 1] = {
    "<leader>ad",
    function() require("codecompanion").prompt("diff-review") end,
    desc = "Review Git diff with Copilot",
  }
end

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
    -- the AI menu runs these before any AI key has loaded the plugin
    cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions", "CodeCompanionCmd" },
    keys = codecompanion_keys,
    config = function()
      require("util.ai_chat").setup()
      require("util.ollama_queue").setup_codecompanion()
      local http_adapters = {
        ollama = function()
          return require("codecompanion.adapters").extend("ollama", {
            schema = {
              model = { default = ollama_model() },
              num_ctx = { default = tuning.chat.num_ctx },
              think = { default = tuning.chat.think },
              keep_alive = { default = tuning.chat.keep_alive },
            },
          })
        end,
        -- <leader>ai: capped output, no thinking, with host-specific context
        -- and retention. Chat follows this host's own profile.
        ollama_fast = function()
          return require("codecompanion.adapters").extend("ollama", {
            schema = {
              model = { default = ollama_model() },
              num_ctx = { default = tuning.inline.num_ctx },
              think = { default = false },
              keep_alive = { default = tuning.inline.keep_alive },
              num_predict = {
                order = 13,
                mapping = "parameters.options",
                type = "number",
                optional = true,
                default = tuning.inline.num_predict,
                desc = "Cap response length for fast inline edits.",
              },
            },
          })
        end,
      }
      http_adapters.copilot = copilot_configured and function()
        return require("codecompanion.adapters").extend("copilot", {
          schema = {
            model = { default = copilot_model },
            reasoning_effort = { default = copilot_reasoning_effort },
          },
        })
      end or false
      http_adapters.opts = { hidden = { copilot = not copilot_configured } }

      local prompt_library = {}
      if copilot_configured then
        prompt_library = {
          ["Review current code"] = {
            interaction = "chat",
            description = "Review the current code for actionable issues",
            opts = { adapter = { name = "copilot" } },
            prompts = {
              {
                role = "system",
                content = "Review code carefully. Report only actionable correctness, security, or maintainability issues, ordered by severity. Do not invent problems or rewrite unrelated code.",
              },
              {
                role = "user",
                content = "Review the code currently in context. Give each finding a concise explanation and point to the relevant code.",
              },
            },
          },
          ["Write tests for current code"] = {
            interaction = "chat",
            description = "Plan tests for the current code using project conventions",
            opts = { adapter = { name = "copilot" } },
            prompts = {
              {
                role = "system",
                content = "You are a pragmatic testing assistant. Follow the project's existing test conventions and focus on meaningful behavior and edge cases.",
              },
              {
                role = "user",
                content = "For the code currently in context, identify the most valuable tests to add. Show the test code and briefly explain what each test protects.",
              },
            },
          },
          ["Review Git diff"] = {
            interaction = "chat",
            description = "Review staged and unstaged Git changes with Copilot",
            opts = {
              alias = "diff-review",
              adapter = { name = "copilot" },
              auto_submit = true,
            },
            prompts = {
              {
                role = "system",
                content = "Review the changes for actionable bugs, regressions, security issues, or data-loss risks. Report findings ordered by severity with file and changed-line references. Do not report style issues or rewrite the code. If there are no findings, say so clearly.",
              },
              {
                role = "user",
                content = "Review the staged and unstaged changes in the current Git repository. If no diff is available, tell me there are no staged or unstaged changes to review.\n\n#{diff}",
              },
            },
          },
        }
      end

      require("codecompanion").setup({
        adapters = {
          http = http_adapters,
        },
        prompt_library = prompt_library,
        interactions = {
          background = { adapter = copilot_configured and "copilot" or "ollama" },
          chat = {
            adapter = copilot_configured and "copilot" or "ollama",
            -- narrower, sidebar-like panel, closer to VS Code's Copilot Chat
            window = { width = 0.35 },
            show_context = true,
            fold_context = false,
            keymaps = {
              back_to_code = {
                modes = { n = "gb" },
                callback = function() require("util.ai_chat").back() end,
                description = "Back to code (keep chat open)",
              },
              -- Copilot Chat's "+" attach-context button: fuzzy list of
              -- every context type and slash command, no # / syntax to recall.
              add_context = {
                modes = { n = "<C-g>", i = "<C-g>" },
                callback = function(chat) require("codecompanion.interactions.chat.action_palette").launch(chat) end,
                description = "Add context",
                index = 1,
              },
              remove_context = {
                modes = { n = "<C-x>" },
                callback = function(chat)
                  local line = vim.api.nvim_get_current_line()
                  local rendered_id = line:match("^> %- (.+)$")
                  if not rendered_id then
                    return vim.notify("Place the cursor on an attached context item", vim.log.levels.WARN)
                  end

                  local icons = require("codecompanion.config").display.chat.icons
                  for _, item in ipairs(chat.context_items) do
                    local item_id = item.id
                    if item.opts and item.opts.sync_all then
                      item_id = icons.sync_all .. item_id
                    elseif item.opts and item.opts.sync_diff then
                      item_id = icons.sync_diff .. item_id
                    end
                    if rendered_id == item_id then
                      chat.context:remove_items({ [item.id] = true })
                      chat:check_context()
                      return
                    end
                  end

                  vim.notify("No attached context on this line", vim.log.levels.WARN)
                end,
                description = "Remove attached context under cursor",
                index = 2,
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
    keys = {
      { "<leader>ag", "<cmd>Minuet virtualtext toggle<cr>", desc = "Toggle AI ghost text" },
    },
    config = function()
      ollama.setup()
      require("minuet").setup({
        provider = "openai_compatible",
        n_completions = 1, -- resource saving for a local model
        context_window = tuning.completion.context_window, -- characters
        request_timeout = tuning.completion.request_timeout,
        throttle = tuning.completion.throttle,
        debounce = tuning.completion.debounce,
        provider_options = {
          openai_compatible = {
            name = "Ollama",
            end_point = "http://localhost:11434/v1/chat/completions",
            api_key = function() return "ollama" end, -- unused, but required to be non-nil
            model = ollama.cached_model(),
            optional = {
              max_tokens = tuning.completion.max_tokens,
              temperature = tuning.completion.temperature,
              reasoning_effort = "none", -- /v1 thinking control; `think` is native /api only
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
      require("util.ollama_queue").setup_minuet()
    end,
  },
}
