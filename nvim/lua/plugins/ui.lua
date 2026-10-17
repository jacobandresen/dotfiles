return {
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "retrobox" },
  },
  { "akinsho/bufferline.nvim", enabled = false },

  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      opts.dashboard = { enabled = false }
      opts.styles = vim.tbl_deep_extend("force", opts.styles or {}, {
        notification = { wo = { winblend = 0 } },
      })
    end,
  },

  -- Markdown source in Edit mode, rendered text in View mode.
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

  {
    "folke/noice.nvim",
    opts = {
      views = { mini = { win_options = { winblend = 0 } } },
    },
  },
}
