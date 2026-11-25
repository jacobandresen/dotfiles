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
    "folke/snacks.nvim",
    init = function() require("util.pi_issues_ui").setup() end,
    -- <leader>aa / ag / av / ae / af / aR / am / ar are mapped (and listed by
    -- which-key) only while their context is live; pi_issues_ui.setup owns them.
    keys = {
      { "<leader>aq", function() require("util.pi_issues").quit() end, desc = "Stop Pi Agents and Quit" },
      {
        "<leader>ai",
        function() require("util.pi_issues_ui").tasks() end,
        desc = "Choose Local Tasks for Pi",
      },
      {
        "<leader>an",
        function() require("util.pi_issues_ui").new_task() end,
        desc = "Write a New Local Task",
      },
      {
        "<leader>aG",
        function() require("util.pi_issues_ui").toggle_github() end,
        desc = "Toggle GitHub Issue Integration",
      },
      {
        "<leader>aw",
        function() require("util.pi_issues_ui").dashboard() end,
        desc = "Pi Task Workspaces",
      },
      {
        "<leader>ap",
        function() require("util.agents").toggle(true) end,
        desc = "Pi Agent",
      },
      {
        "<F6>",
        function()
          vim.cmd.stopinsert()
          require("util.agents").toggle()
        end,
        mode = { "n", "t" },
        desc = "Hide / Show Pi Agent",
      },
    },
  },
}
