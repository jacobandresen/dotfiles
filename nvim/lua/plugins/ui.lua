return {
  {
    "lifepillar/vim-solarized8",
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "solarized8" },
  },
  {
    "nvim-lualine/lualine.nvim",
    opts = {
      options = {
        theme = "auto",
        globalstatus = true,
        component_separators = { left = "│", right = "│" },
        section_separators = { left = "", right = "" },
      },
      sections = {
        lualine_a = { { "mode", separator = { left = "", right = "" } } },
        lualine_b = { "branch", "diff", "diagnostics" },
        lualine_c = { { "filename", path = 1 } },
        lualine_x = { "encoding", "fileformat", "filetype" },
        lualine_y = { "progress" },
        lualine_z = { { "location", separator = { left = "", right = "" } } },
      },
    },
  },
  { "akinsho/bufferline.nvim", enabled = false },

  {
    "folke/snacks.nvim",
    init = function()
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("solarized_picker_highlights", { clear = true }),
        callback = function()
          local set = vim.api.nvim_set_hl
          set(0, "SnacksPicker", { fg = "#657b83", bg = "#fdf6e3" })
          set(0, "SnacksPickerBorder", { fg = "#93a1a1", bg = "#fdf6e3" })
          set(0, "SnacksPickerTitle", { fg = "#268bd2", bg = "#fdf6e3", bold = true })
          set(0, "SnacksPickerPrompt", { fg = "#268bd2", bg = "#eee8d5", bold = true })
          set(0, "SnacksPickerInput", { fg = "#657b83", bg = "#eee8d5" })
          set(0, "SnacksPickerList", { fg = "#657b83", bg = "#fdf6e3" })
          set(0, "SnacksPickerCursorLine", { fg = "#586e75", bg = "#eee8d5" })
          set(0, "SnacksPickerMatch", { fg = "#cb4b16", bold = true })
          set(0, "SnacksPickerDir", { fg = "#2aa198" })
          set(0, "SnacksPickerFile", { fg = "#657b83" })
          set(0, "SnacksPickerTree", { fg = "#93a1a1" })
        end,
      })
    end,
    opts = function(_, opts)
      -- Start in a plain editor window.
      opts.dashboard = { enabled = false }
      -- opaque notifications (see fidget below)
      opts.styles = vim.tbl_deep_extend("force", opts.styles or {}, {
        notification = { wo = { winblend = 0 } },
        -- Keep lazygit/lazydocker easy to close from any panel.
        lazygit = {
          border = "double",
          title = " Lazygit ",
          title_pos = "center",
          footer = " Alt+X Close ",
          footer_pos = "center",
          keys = {
            close = { "<M-x>", "hide", mode = { "t", "n" }, desc = "Close" },
          },
        },
      })

      -- Compact explorer with a clear input line and no distracting icons.
      local sidebar = {
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
      }
      opts.picker = vim.tbl_deep_extend("force", opts.picker or {}, {
        sources = {
          explorer = sidebar,
        },
      })

      return opts
    end,
  },

  -- Reference counts are opt-in per buffer to avoid background LSP work.
  {
    "Wansmer/symbol-usage.nvim",
    keys = {
      { "<leader>uR", function()
        local buf = vim.api.nvim_get_current_buf()
        vim.b[buf].symbol_usage_enabled = not vim.b[buf].symbol_usage_enabled
        require("symbol-usage").refresh()
      end, desc = "Toggle Symbol Reference Counts" },
    },
    opts = {
      hl = { link = "LspCodeLens" },
      disable = { cond = { function(buf) return not vim.b[buf].symbol_usage_enabled end } },
    },
  },

  -- sign-column wand: shows when a quickfix is available at the cursor,
  -- use normal code actions for individual fixes; <leader>cF handles
  -- document-wide LSP, compiler and linter fixes.
  {
    "kosayoda/nvim-lightbulb",
    event = "LspAttach",
    opts = {
      autocmd = { enabled = true },
      action_kinds = { "quickfix" },
      sign = { text = "🪄" },
    },
  },

  -- markdown rendering, only in View mode (util/mdview.lua): Edit shows the
  -- source, View renders every line including the cursor's
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    init = function()
      require("util.mdview").setup()
    end,
    keys = {
      { "<leader>um", function() require("util.mdview").toggle() end, ft = "markdown", desc = "Markdown View/Edit" },
    },
    opts = {
      enabled = false,
      anti_conceal = { enabled = false },
    },
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
