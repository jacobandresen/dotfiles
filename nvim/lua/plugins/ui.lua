-- Lean UI: classic cmdline, flat statusline, no animations or decorations.
return {
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "retrobox",
      news = { lazyvim = false, neovim = false }, -- no changelog popups
    },
  },
  { "akinsho/bufferline.nvim", enabled = false },
  { "folke/noice.nvim", enabled = false }, -- native cmdline/messages
  { "folke/todo-comments.nvim", enabled = false },

  {
    "folke/snacks.nvim",
    opts = {
      dashboard = { enabled = false },
      indent = { enabled = false },
      scope = { enabled = false },
      scroll = { enabled = false },
      words = { enabled = false },
      notifier = { style = "minimal", top_down = false },
      picker = {
        sources = {
          -- bare tree: no search box (press / or i to filter), narrower
          explorer = { layout = { hidden = { "input" }, layout = { width = 30 } } },
        },
      },
      styles = { notification = { wo = { winblend = 0 } } },
    },
  },

  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      opts.options.section_separators = ""
      opts.options.component_separators = ""
      opts.sections.lualine_a = { { "mode", fmt = function(m) return m:sub(1, 1) end } }
      opts.sections.lualine_y = { "location" }
      opts.sections.lualine_z = {}
    end,
  },

  {
    "saghen/blink.cmp",
    opts = {
      completion = {
        menu = { draw = { treesitter = {} } }, -- plain labels, cheaper redraws
        documentation = { auto_show_delay_ms = 500 },
      },
    },
  },

  {
    "folke/which-key.nvim",
    opts = {
      preset = "helix",
      delay = 400,
      -- no popup on plain v/V; Space still opens it in Visual mode
      triggers = { { "<auto>", mode = "nso" }, { "<leader>", mode = "x" } },
      icons = { mappings = false, separator = " " },
      spec = {
        { "<leader>a", group = "ai" },
        { "<leader>D", group = "database" },
      },
    },
  },

  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    keys = {
      { "<leader>um", "<cmd>RenderMarkdown buf_toggle<cr>", ft = "markdown", desc = "Toggle Markdown Rendering" },
    },
    opts = {
      enabled = false,
      anti_conceal = { enabled = false },
    },
  },
}
