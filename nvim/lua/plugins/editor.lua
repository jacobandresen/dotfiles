return {
  -- disable neo-tree: use the Snacks explorer instead (enabled via the
  -- snacks_explorer extra in lazyvim.json, <leader>e)
  { "nvim-neo-tree/neo-tree.nvim", enabled = false },

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

  -- folding
  {
    "kevinhwang91/nvim-ufo",
    dependencies = { "kevinhwang91/promise-async" },
    config = function()
      local ufo = require("ufo")

      local function fold_handler(virtText, lnum, endLnum, width, truncate)
        local newVirtText = {}
        local suffix = (" 󰁂 %d "):format(endLnum - lnum)
        local sufWidth = vim.fn.strdisplaywidth(suffix)
        local targetWidth = width - sufWidth
        local curWidth = 0
        for _, chunk in ipairs(virtText) do
          local chunkText = chunk[1]
          local chunkWidth = vim.fn.strdisplaywidth(chunkText)
          if targetWidth > curWidth + chunkWidth then
            table.insert(newVirtText, chunk)
          else
            chunkText = truncate(chunkText, targetWidth - curWidth)
            local hlGroup = chunk[2]
            table.insert(newVirtText, { chunkText, hlGroup })
            chunkWidth = vim.fn.strdisplaywidth(chunkText)
            if curWidth + chunkWidth < targetWidth then
              suffix = suffix .. (" "):rep(targetWidth - curWidth - chunkWidth)
            end
            break
          end
          curWidth = curWidth + chunkWidth
        end
        table.insert(newVirtText, { suffix, "MoreMsg" })
        return newVirtText
      end

      ufo.setup({
        provider_selector = function(_, _, _)
          return { "treesitter", "indent" }
        end,
        fold_virt_text_handler = fold_handler,
        close_fold_kinds_for_ft = { default = { "imports", "comments" } },
      })

      vim.keymap.set("n", "zR", ufo.openAllFolds, { desc = "Open All Folds" })
      vim.keymap.set("n", "zM", ufo.closeAllFolds, { desc = "Close All Folds" })
      vim.keymap.set("n", "zr", ufo.openFoldsExceptKinds, { desc = "Open Folds (except imports/comments)" })
      vim.keymap.set("n", "zm", ufo.closeFoldsWith, { desc = "Close Folds With Level" })
    end,
  },

  -- K peeks a closed fold, otherwise hovers. Must go through LazyVim's LSP
  -- keys: a plain keymap would be shadowed by its buffer-local K on attach.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ["*"] = {
          keys = {
            {
              "K",
              function()
                if not require("ufo").peekFoldedLinesUnderCursor() then
                  vim.lsp.buf.hover()
                end
              end,
              desc = "Peek Fold / Hover",
            },
          },
        },
      },
    },
  },

  -- telescope: `opts` merges into the telescope extra's config (which also
  -- builds and loads fzf-native); a `config` here would discard its mappings
  {
    "nvim-telescope/telescope.nvim",
    opts = {
      defaults = {
        layout_strategy = "vertical",
        layout_config = { height = 0.95, width = 0.99 },
        file_ignore_patterns = { "node_modules/", "%.git/", "%.lock" },
        borderchars = { "═", "║", "═", "║", "╔", "╗", "╝", "╚" }, -- Turbo Vision frames
      },
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
        jsonc = { "jq" },
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
      formatters = {
        prettier = {
          prepend_args = { "--end-of-line", "lf" },
        },
        stylua = {
          prepend_args = { "--indent-type", "Spaces", "--indent-width", "2" },
        },
      },
    },
  },

  -- indent guides come from snacks.indent (LazyVim default); no scope line
  {
    "folke/snacks.nvim",
    opts = { indent = { scope = { enabled = false } } },
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
      "tpope/vim-dadbod",
      "kristijanhusak/vim-dadbod-completion",
    },
    cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer", "DBUIRenameBuffer", "DBUILastQueryInfo" },
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
