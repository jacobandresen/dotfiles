return {
  -- file explorer
  {
    "stevearc/oil.nvim",
    lazy = false,
    dependencies = { { "nvim-mini/mini.icons", opts = {} } },
    config = function()
      require("oil").setup({
        view_options = {
          show_hidden = true,
          is_hidden_file = function() return false end,
          is_always_hidden = function() return false end,
        },
        keymaps = {
          ["gy"] = {
            callback = function()
              local oil = require("oil")
              local entry = oil.get_cursor_entry()
              local dir = oil.get_current_dir()
              if entry and dir then
                local path = dir .. entry.name
                vim.fn.setreg("+", path)
                vim.notify("Copied: " .. path)
              end
            end,
            desc = "Copy absolute path",
          },
        },
        use_default_keymaps = true,
        skip_confirm_for_simple_edits = false,
      })
    end,
  },

  -- disable neo-tree since we use oil
  { "nvim-neo-tree/neo-tree.nvim", enabled = false },

  -- tmux/nvim split navigation
  {
    "alexghergh/nvim-tmux-navigation",
    config = function()
      require("nvim-tmux-navigation").setup({
        disable_when_zoomed = true,
        keybindings = {
          left = "<C-h>",
          down = "<C-j>",
          up = "<C-k>",
          right = "<C-l>",
          last_active = "<C-b>",
          next = "<C-n>",
        },
      })
    end,
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
        fold_virt_text_handler = fold_handler,
        close_fold_kinds_for_ft = { default = { "imports", "comments" } },
      })

      vim.keymap.set("n", "zR", ufo.openAllFolds)
      vim.keymap.set("n", "zM", ufo.closeAllFolds)
      vim.keymap.set("n", "zr", ufo.openFoldsExceptKinds)
      vim.keymap.set("n", "zm", ufo.closeFoldsWith)
      vim.keymap.set("n", "K", function()
        local winid = ufo.peekFoldedLinesUnderCursor()
        if not winid then
          vim.lsp.buf.hover()
        end
      end)
    end,
  },

  -- telescope config
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope-fzf-native.nvim" },
    config = function()
      require("telescope").setup({
        defaults = {
          layout_strategy = "vertical",
          layout_config = { height = 0.95, width = 0.99 },
          file_ignore_patterns = { "node_modules/", ".git/", "%.lock" },
          hidden = true,
        },
      })
      require("telescope").load_extension("fzf")
    end,
  },

  { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },

  -- formatting with conform.nvim
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    config = function()
      require("conform").setup({
        formatters_by_ft = {
          lua = { "stylua" },
          javascript = { "prettier" },
          typescript = { "prettier" },
          javascriptreact = { "prettier" },
          typescriptreact = { "prettier" },
          json = { "jq" },
          jsonc = { "jq" },
          rust = { "rustfmt" },
          cpp = { "clang-format" },
          c = { "clang-format" },
          cs = { "dotnet-format" },
          yaml = { "prettier" },
          markdown = { "prettier" },
          html = { "prettier" },
          css = { "prettier" },
          sh = { "shfmt" },
          python = { "black", "isort" },
          go = { "gofmt", "goimports" },
        },
        format_on_save = function(bufnr)
          local disable_filetypes = {}
          return {
            timeout_ms = 500,
            lsp_fallback = not disable_filetypes[vim.bo[bufnr].filetype],
          }
        end,
        formatters = {
          -- Custom formatter for markdown with frontmatter support
          prettier = {
            prepend_args = function()
              return { "--end-of-line", "lf" }
            end,
          },
          stylua = {
            prepend_args = { "--indent-type", "Spaces", "--indent-width", "2" },
          },
        },
      })
    end,
  },

  -- indent guides
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    event = "BufReadPre",
    opts = {
      indent = {
        char = "│",
        tab_char = "│",
      },
      scope = {
        enabled = false,
      },
      exclude = {
        filetypes = {
          "lspinfo",
          "packer",
          "checkhealth",
          "help",
          "man",
          "dashboard",
          "lazy",
          "mason",
          "notify",
          "toggleterm",
          "oil",
          "TelescopePrompt",
          "TelescopeResults",
        },
        buftypes = {
          "terminal",
          "nofile",
        },
      },
    },
  },
}
