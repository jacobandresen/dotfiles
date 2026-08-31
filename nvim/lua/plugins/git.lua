return {
  -- git signs in gutter
  {
    "lewis6991/gitsigns.nvim",
    event = "BufReadPre",
    opts = {
      signs = {
        add = { text = "┃" },
        change = { text = "┃" },
        delete = { text = "▁" },
        topdelete = { text = "▔" },
        changedelete = { text = "~" },
      },
      signs_staged = {
        add = { text = "┃" },
        change = { text = "┃" },
        delete = { text = "▁" },
        topdelete = { text = "▔" },
        changedelete = { text = "~" },
      },
      signs_staged_enable = true,
      signcolumn = true,
      numhl = false,
      linehl = false,
      word_diff = false,
      watch_gitdir = {
        interval = 1000,
        follow_files = true,
      },
      attach_to_untracked = true,
      current_line_blame = true,
      current_line_blame_opts = {
        virt_text = true,
        virt_text_pos = "eol",
        delay = 100,
        ignore_whitespace = false,
      },
      current_line_blame_formatter = "<author>, <author_time:%Y-%m-%d> - <summary>",
      sign_priority = 6,
      update_debounce = 100,
      status_formatter = nil,
      max_file_length = 40000,
      preview_config = {
        border = "rounded",
        style = "minimal",
        relative = "cursor",
        row = 0,
        col = 1,
      },
      yadm = {
        enable = false,
      },
      on_attach = function(bufnr)
        local gs = package.loaded.gitsigns
        local map = vim.keymap.set

        -- Navigation
        map("n", "]c", function()
          if vim.wo.diff then
            return "]c"
          end
          vim.schedule(function()
            gs.next_hunk()
          end)
          return "<Ignore>"
        end, { buffer = bufnr, expr = true, desc = "Next hunk" })

        map("n", "[c", function()
          if vim.wo.diff then
            return "[c"
          end
          vim.schedule(function()
            gs.prev_hunk()
          end)
          return "<Ignore>"
        end, { buffer = bufnr, expr = true, desc = "Previous hunk" })

        -- Actions (using <leader>h prefix to avoid conflict with Telescope <leader>g)
        map("n", "<leader>hb", gs.blame_line, { buffer = bufnr, desc = "Blame line" })
        map("n", "<leader>hd", gs.diffthis, { buffer = bufnr, desc = "Diff this" })
        map("n", "<leader>hD", function()
          gs.diffthis("~")
        end, { buffer = bufnr, desc = "Diff against HEAD~" })
        map("n", "<leader>hp", gs.preview_hunk, { buffer = bufnr, desc = "Preview hunk" })
        map("n", "<leader>hr", gs.reset_hunk, { buffer = bufnr, desc = "Reset hunk" })
        map("n", "<leader>hR", gs.reset_buffer, { buffer = bufnr, desc = "Reset buffer" })
        map("n", "<leader>hs", gs.stage_hunk, { buffer = bufnr, desc = "Stage hunk" })
        map("n", "<leader>hu", gs.undo_stage_hunk, { buffer = bufnr, desc = "Unstage hunk" })
        map("v", "<leader>hs", function()
          gs.stage_hunk({ vim.fn.line("'<"), vim.fn.line(">'") })
        end, { buffer = bufnr, desc = "Stage selected hunk" })
        map("v", "<leader>hr", function()
          gs.reset_hunk({ vim.fn.line("'<"), vim.fn.line(">'") })
        end, { buffer = bufnr, desc = "Reset selected hunk" })

        -- Text object
        map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", { buffer = bufnr, desc = "Select hunk" })
      end,
    },
  },
}
