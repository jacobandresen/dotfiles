vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*.log", "*.jsonl" },
  callback = function(args)
    vim.bo[args.buf].autoread = true
  end,
})

-- only one sidebar at a time: opening the explorer closes the Dadbod drawer
-- and vice versa
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("one_sidebar", { clear = true }),
  pattern = { "snacks_picker_list", "dbui" },
  callback = function(ev)
    vim.schedule(function()
      local explorers = Snacks.picker.get({ source = "explorer" })
      if ev.match == "dbui" then
        for _, picker in ipairs(explorers) do picker:close() end
        return
      end
      for _, picker in ipairs(explorers) do
        if picker.list.win.buf == ev.buf then
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "dbui" then
              return vim.cmd("DBUIClose")
            end
          end
        end
      end
    end)
  end,
})

-- Pick up changes made on disk when focus returns or a buffer is entered.
vim.api.nvim_create_autocmd({ "FocusGained", "TermLeave", "BufEnter" }, {
  group = vim.api.nvim_create_augroup("agent_reload", { clear = true }),
  callback = function()
    vim.schedule(function()
      if vim.fn.mode() ~= "c" and vim.bo.buftype == "" then vim.cmd("checktime") end
    end)
  end,
})
