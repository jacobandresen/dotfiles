-- This config's directory (nvim/): the pi theme lives in it.
local config = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")

return {
  -- Inline AI ghost text (fill-in-the-middle) from the local Ollama
  -- qwen2.5-coder:1.5b-base FIM model (pulled and warmed by `make use-model`).
  -- Snappiness comes from: small model kept hot, streaming, short context,
  -- low max tokens, tight debounce/throttle. <A-j>/<A-k> are LazyVim's — untouched.
  {
    "milanglacier/minuet-ai.nvim",
    opts = {
      notify = "error",
      provider = "openai_fim_compatible",
      n_completions = 1,
      -- characters of code around the cursor (~512 tokens for the FIM model)
      context_window = 2048,
      context_ratio = 0.75,
      throttle = 250,
      debounce = 100,
      request_timeout = 2,
      add_single_line_entry = true,
      provider_options = {
        openai_fim_compatible = {
          api_key = "TERM", -- unused by Ollama; any env var name passes minuet's check
          name = "Ollama",
          end_point = "http://127.0.0.1:11434/v1/completions",
          model = "qwen2.5-coder:1.5b-base",
          optional = {
            max_tokens = 48, -- a few lines; streams in, so latency stays low
            top_p = 0.9,
          },
          -- qwen2.5-coder FIM tokens; the fim model's template is pass-through
          template = {
            prompt = function(context_before_cursor, context_after_cursor, _)
              return "<|fim_prefix|>"
                .. context_before_cursor
                .. "<|fim_suffix|>"
                .. context_after_cursor
                .. "<|fim_middle|>"
            end,
            suffix = false,
          },
        },
      },
      virtualtext = {
        auto_trigger_ft = { "*" },
        auto_trigger_ignore_ft = { "bigfile", "snacks_picker_input", "snacks_picker_list", "oil", "minifiles", "DressingInput", "gitcommit", "markdown" },
        keymap = {
          -- accept whole completion
          accept = "<A-a>",
          -- accept one line
          accept_line = "<A-l>",
          -- accept the next word
          accept_word = "<A-w>",
          -- accept n lines (prompts for a number)
          accept_n_lines = "<A-z>",
          -- cycle to the previous / next completion, or invoke one manually
          prev = "<A-[>",
          next = "<A-]>",
          dismiss = "<A-e>",
        },
      },
    },
  },

  {
    -- Task workspaces for coding agents (latest main; lazy runs its build.lua), run with pi.
    -- 3 agents match OLLAMA_NUM_PARALLEL (ollama/ollama.env); more only queue behind the same
    -- request slots, and each extra running agent slows the others' decoding.
    "jacobandresen/taskbay.nvim",
    lazy = false,
    dependencies = { "folke/snacks.nvim" },
    opts = {
      max_agents = 3,
      state_dir = vim.fn.stdpath("state") .. "/pi-issues", -- keeps workspaces started before the rename
      pi = { args = { "--theme", config .. "/themes/pi-retrobox.json", "--use-theme", "retrobox" } },
    },
  },
}
