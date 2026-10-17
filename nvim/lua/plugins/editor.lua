return {
  -- tmux/nvim split navigation. Mapped via `keys` so LazyVim's own
  -- <C-h/j/k/l> window maps step aside (they'd otherwise override these).
  {
    "alexghergh/nvim-tmux-navigation",
    opts = { disable_when_zoomed = true },
    keys = {
      { "<C-h>", "<cmd>NvimTmuxNavigateLeft<cr>", desc = "Go to Left Window/Pane" },
      { "<C-j>", "<cmd>NvimTmuxNavigateDown<cr>", desc = "Go to Lower Window/Pane" },
      { "<C-k>", "<cmd>NvimTmuxNavigateUp<cr>", desc = "Go to Upper Window/Pane" },
      { "<C-l>", "<cmd>NvimTmuxNavigateRight<cr>", desc = "Go to Right Window/Pane" },
    },
  },

  -- formatting with conform.nvim
  -- NOTE: LazyVim owns conform's `config` and drives format-on-save itself, so
  -- this spec must only contribute `opts` (deep-merged into LazyVim's defaults).
  -- Setting `config` or `format_on_save` here breaks LazyVim formatting.
  {
    "stevearc/conform.nvim",
    opts = {
      -- lua (stylua) and sh (shfmt) are already set by LazyVim
      formatters_by_ft = {
        javascript = { "prettier" },
        typescript = { "prettier" },
        javascriptreact = { "prettier" },
        typescriptreact = { "prettier" },
        json = { "jq" },
        jsonc = { "prettier" },
        rust = { "rustfmt" },
        cpp = { "clang-format" },
        c = { "clang-format" },
        cs = { "csharpier" },
        yaml = { "prettier" },
        markdown = { "prettier" },
        html = { "prettier" },
        css = { "prettier" },
        python = { "black", "isort" },
        go = { "goimports" }, -- goimports also does gofmt's formatting
      },
    },
  },

  -- TP's editor has no indentation guides.
  {
    "folke/snacks.nvim",
    opts = { indent = { enabled = false } },
  },

  -- ensure parsers for every language we debug/edit are installed
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "c_sharp", "rust", "java", "javascript", "typescript", "tsx",
      })
    end,
  },

  -- database support
  {
    "kristijanhusak/vim-dadbod-ui",
    dependencies = {
      { "tpope/vim-dadbod", cmd = "DB" },
      { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" } },
    },
    cmd = { "DBUI", "DBUIToggle", "DBUIClose" },
    keys = {
      { "<leader>Du", "<cmd>DBUIToggle<cr>",        desc = "DB Toggle UI" },
      -- the selection, or the whole buffer, against the buffer's database
      { "<leader>De", function() require("util.db").execute("%") end, desc = "DB Execute Query" },
      { "<leader>De", function() require("util.db").execute("'<,'>") end, mode = "x", desc = "DB Execute Selection" },
    },
    init = function()
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/db_ui"
      vim.g.db_ui_show_help = 0
      -- Saving is separate from executing; avoid accidental duplicate writes.
      vim.g.db_ui_execute_on_save = 0
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("dbui_keys", { clear = true }),
        pattern = "dbui",
        callback = function(args)
          vim.keymap.set("n", "<Esc>", "<cmd>DBUIClose<cr>", {
            buffer = args.buf,
            desc = "Close Database UI",
          })
        end,
      })
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
