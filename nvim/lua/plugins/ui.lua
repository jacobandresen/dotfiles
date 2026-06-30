return {
  -- dashboard: TurboVim block logo (replaces LazyVim default header)
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      local head = "SnacksDashboardHeader"
      local function line(str)
        return { str .. "\n", hl = head, align = "center" }
      end

      opts.dashboard = opts.dashboard or {}
      opts.dashboard.sections = {
        {
          padding = 1,
          text = {
            line("████████ ██    ██ ██████  ██████   ██████  ██    ██ ██ ███    ███"),
            line("   ██    ██    ██ ██   ██ ██   ██ ██    ██ ██    ██ ██ ████  ████"),
            line("   ██    ██    ██ ██████  ██████  ██    ██ ██    ██ ██ ██ ████ ██"),
            line("   ██    ██    ██ ██   ██ ██   ██ ██    ██  ██  ██  ██ ██  ██  ██"),
            line("   ██     ██████  ██   ██ ██████   ██████    ████   ██ ██      ██"),
          },
        },
        { section = "keys", gap = 1, padding = 1 },
        { section = "startup" },
      }
      return opts
    end,
  },

  -- lualine: show full file path
  {
    "nvim-lualine/lualine.nvim",
    opts = {
      sections = {
        lualine_c = { { "filename", path = 4 } },
      },
    },
  },

  -- LSP usage counts shown inline
  {
    "Wansmer/symbol-usage.nvim",
    event = "LspAttach",
    config = function()
      require("symbol-usage").setup()
    end,
  },

  -- markdown rendering
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    opts = {},
    ft = { "markdown" },
  },

  -- LSP status spinner
  {
    "j-hui/fidget.nvim",
    config = function()
      require("fidget").setup()
    end,
  },
}
