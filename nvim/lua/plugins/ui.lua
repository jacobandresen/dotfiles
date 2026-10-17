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

  {
    "folke/noice.nvim",
    opts = {
      views = { mini = { win_options = { winblend = 0 } } },
    },
  },
}
