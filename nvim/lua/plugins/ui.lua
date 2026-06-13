return {
  -- dashboard: matrix-rain Neovim logo with green binary rain (replaces LazyVim default header)
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      -- Matrix-green highlight for the binary rain; re-applied on colorscheme change
      local function set_matrix_hl()
        vim.api.nvim_set_hl(0, "SnacksDashboardMatrix", { fg = "#00ff41", bold = true })
      end
      set_matrix_hl()
      vim.api.nvim_create_autocmd("ColorScheme", { callback = set_matrix_hl })

      local rain = "SnacksDashboardMatrix"
      local head = "SnacksDashboardHeader"
      local function line(str, hl)
        return { str .. "\n", hl = hl, align = "center" }
      end

      opts.dashboard = opts.dashboard or {}
      opts.dashboard.sections = {
        {
          padding = 1,
          text = {
            line(" 1 0 1 1 0    0 1 0 0 1 1 0    1 1 0 0 1 0    1 0 1 1", rain),
            line("███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗", head),
            line("████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║", head),
            line("██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║", head),
            line("██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║", head),
            line("██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║", head),
            line("╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝", head),
            line(" 0 1 1 0 1    1 0 1 1 0 0 1    0 0 1 1 0 1    0 1 1 0", rain),
            line("       // wake up, neo... the editor has you", rain),
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
    ft = { "markdown", "codecompanion" },
  },

  -- LSP status spinner
  {
    "j-hui/fidget.nvim",
    config = function()
      require("fidget").setup()
    end,
  },
}
