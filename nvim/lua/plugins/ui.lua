return {
  -- Turbo Pascal 7.0 look: colors/turbopascal.lua plus lua/turbo/ (menu bar
  -- in the tabline, hint line in the statusline), which replace lualine and
  -- bufferline
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "turbopascal" },
  },
  { "nvim-lualine/lualine.nvim", enabled = false },
  { "akinsho/bufferline.nvim", enabled = false },

  -- dashboard: TurboVim block logo (replaces LazyVim default header)
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      local head = "SnacksDashboardHeader"
      local function line(str)
        return { str .. "\n", hl = head, align = "center" }
      end

      -- opaque notifications (see fidget below)
      opts.styles = vim.tbl_deep_extend("force", opts.styles or {}, {
        notification = { wo = { winblend = 0 } },
        -- lazygit/lazydocker: Alt+X (or TP's Alt+F3 "Close") quits from any
        -- lazygit panel, instead of hunting for the view where q works
        lazygit = {
          border = "double",
          title = " Lazygit ",
          title_pos = "center",
          footer = " Alt+X Close ",
          footer_pos = "center",
          keys = {
            turbo_close = { "<M-x>", "hide", mode = { "t", "n" }, desc = "Close" },
            turbo_close_f3 = { "<M-F3>", "hide", mode = { "t", "n" }, desc = "Close" },
            turbo_close_f51 = { "<F51>", "hide", mode = { "t", "n" }, desc = "Close" }, -- Alt+F3, xterm style
          },
        },
      })

      -- explorer as a Turbo Vision window: one double frame with a centred
      -- title, a TP input line and no Nerd Font icons (colours: SnacksPicker*
      -- in colors/turbopascal.lua)
      opts.picker = vim.tbl_deep_extend("force", opts.picker or {}, {
        sources = {
          explorer = {
            prompt = "> ",
            icons = {
              files = { enabled = false },
              tree = { vertical = "│ ", middle = "├─", last = "└─" },
            },
            layout = {
              preview = false,
              layout = {
                backdrop = false,
                width = 34,
                min_width = 34,
                height = 0,
                position = "left",
                box = "vertical",
                border = "double",
                title = " {title} {flags}",
                title_pos = "center",
                { win = "input", height = 1, border = "bottom" },
                { win = "list", border = "none" },
              },
            },
          },
        },
      })

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
            { "\nA tribute to Borland Turbo Pascal 7.0\n", hl = "SnacksDashboardFooter", align = "center" },
          },
        },
        { section = "keys", gap = 1, padding = 1 },
        { section = "startup" },
      }
      return opts
    end,
  },

  -- LSP usage counts shown inline (cyan, like inlay hints, not comments)
  {
    "Wansmer/symbol-usage.nvim",
    event = "LspAttach",
    opts = { hl = { link = "LspCodeLens" } },
  },

  -- sign-column wand: shows when a quickfix is available at the cursor,
  -- matching what <leader>cF (autocmds.lua) applies in bulk
  {
    "kosayoda/nvim-lightbulb",
    event = "LspAttach",
    opts = {
      autocmd = { enabled = true },
      action_kinds = { "quickfix" },
      sign = { text = "🪄" },
    },
  },

  -- markdown rendering
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    opts = {},
  },

  -- LSP progress spinner (also used by ai.lua's inline-edit spinner).
  -- Noice's own LSP progress is turned off so there's only one.
  -- Status messages get opaque grey boxes: any winblend lets the code
  -- underneath show through blank cells, which made them hard to read.
  {
    "j-hui/fidget.nvim",
    event = "LspAttach",
    opts = {
      progress = {
        display = {
          done_style = "TurboStatusMsgTitle",
          progress_style = "TurboStatusMsgDim",
          group_style = "TurboStatusMsgTitle",
          icon_style = "TurboStatusMsgIcon",
        },
      },
      notification = {
        window = {
          normal_hl = "TurboStatusMsg",
          winblend = 0,
          border = "single",
          border_hl = "TurboStatusMsg",
        },
      },
    },
  },
  {
    "folke/noice.nvim",
    opts = {
      lsp = { progress = { enabled = false } },
      views = { mini = { win_options = { winblend = 0 } } },
    },
  },
}
