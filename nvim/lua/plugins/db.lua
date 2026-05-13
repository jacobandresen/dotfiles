return {
  { "tpope/vim-dadbod", lazy = true },

  {
    "kristijanhusak/vim-dadbod-completion",
    dependencies = { "tpope/vim-dadbod" },
    lazy = true,
  },

  {
    "kristijanhusak/vim-dadbod-ui",
    dependencies = {
      "tpope/vim-dadbod",
      "kristijanhusak/vim-dadbod-completion",
    },
    cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
    keys = {
      { "<leader>Du", "<cmd>DBUIToggle<cr>",        desc = "DB Toggle UI" },
      { "<leader>Da", "<cmd>DBUIAddConnection<cr>", desc = "DB Add Connection" },
      { "<leader>Df", "<cmd>DBUIFindBuffer<cr>",    desc = "DB Find Buffer" },
    },
    init = function()
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/db_ui"
      vim.g.db_ui_show_help = 0
    end,
  },

  -- register dadbod as a blink.cmp source for sql filetypes
  {
    "saghen/blink.cmp",
    opts = {
      sources = {
        providers = {
          dadbod = {
            name = "Dadbod",
            module = "vim_dadbod_completion.blink",
          },
        },
        per_filetype = {
          sql = { "dadbod", "buffer" },
          mysql = { "dadbod", "buffer" },
          plsql = { "dadbod", "buffer" },
        },
      },
    },
  },
}
