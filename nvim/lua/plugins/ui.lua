return {
  -- colorscheme: solarized-osaka (Tokyonight-engine based Solarized)
  {
    "craftzdog/solarized-osaka.nvim",
    lazy = false,
    priority = 1000,
    opts = {},
  },

  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "solarized-osaka" },
  },

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

  -- sign-column wand: shows when a quickfix is available at the cursor,
  -- matching what <leader>cF (autocmds.lua) applies in bulk
  {
    "kosayoda/nvim-lightbulb",
    event = "LspAttach",
    config = function()
      require("nvim-lightbulb").setup({
        autocmd = { enabled = true },
        action_kinds = { "quickfix" },
        sign = { text = "🪄" },
      })
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
