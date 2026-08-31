return {
  -- colorscheme: solarized-osaka (Tokyonight-engine based Solarized)
  {
    "craftzdog/solarized-osaka.nvim",
    lazy = false,
    priority = 1000,
    init = function()
      vim.o.background = "light"
    end,
    opts = {},
  },

  -- colorscheme: borlandp (classic Borland Turbo Pascal/Turbo C++ look)
  {
    "caglartoklu/borlandp.vim",
    lazy = true,
    priority = 1000,
    init = function()
      vim.g.borlandp_bg = "borland_blue"

      -- borlandp.vim runs `hi clear` on load, so re-apply oil.nvim (file
      -- explorer) highlights every time the colorscheme is (re)loaded.
      vim.api.nvim_create_autocmd("ColorScheme", {
        pattern = "borlandp",
        callback = function()
          local links = {
            OilDir = "Directory",
            OilDirIcon = "Directory",
            OilFile = "Normal",
            OilLink = "Special",
            OilLinkTarget = "Special",
            OilSocket = "Constant",
            OilCreate = "Directory",
            OilChange = "Normal",
            OilRestore = "Directory",
            OilCopy = "Special",
            OilMove = "Constant",
            OilDelete = "WarningMsg",
            OilPurge = "WarningMsg",
            OilOrphanLink = "WarningMsg",
            OilOrphanLinkTarget = "WarningMsg",
            OilTrash = "Comment",
            OilTrashSourcePath = "Comment",
            OilVtext = "Comment",
            OilHidden = "Comment",
            OilDirHidden = "Comment",
            OilFileHidden = "Comment",
            OilLinkHidden = "Comment",
            OilSocketHidden = "Comment",
            OilOrphanLinkHidden = "Comment",
            OilOrphanLinkTargetHidden = "Comment",
            OilEmpty = "Comment",
            OilEnter = "Search",
            OilPreviewCursor = "CursorLine",

            -- mini.icons: the file/dir icons oil.nvim renders are colored
            -- via these groups, not the Oil* ones above, and default-link
            -- to unrelated Diagnostic* colors that borlandp never touches.
            MiniIconsAzure = "Special",
            MiniIconsBlue = "Statement",
            MiniIconsCyan = "Special",
            MiniIconsGreen = "Directory",
            MiniIconsGrey = "Comment",
            MiniIconsOrange = "WarningMsg",
            MiniIconsPurple = "Constant",
            MiniIconsRed = "WarningMsg",
            MiniIconsYellow = "Normal",
          }
          for group, target in pairs(links) do
            vim.api.nvim_set_hl(0, group, { link = target })
          end
        end,
      })
    end,
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
