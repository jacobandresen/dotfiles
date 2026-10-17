vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*.log", "*.jsonl" },
  callback = function(args)
    vim.bo[args.buf].autoread = true
  end,
})

-- only one sidebar at a time: the file explorer or the Dadbod drawer
local sidebar_pickers = { explorer = true }

local function close_sidebars(keep)
  for _, picker in ipairs(Snacks.picker.get()) do
    if sidebar_pickers[picker.opts.source] and picker.opts.source ~= keep then
      picker:close()
    end
  end
  if keep ~= "dbui" then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "dbui" then
        vim.cmd("DBUIClose")
        break
      end
    end
  end
end

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("one_sidebar", { clear = true }),
  pattern = { "snacks_picker_list", "dbui" },
  callback = function(ev)
    vim.schedule(function()
      if ev.match == "dbui" then
        return close_sidebars("dbui")
      end
      for _, picker in ipairs(Snacks.picker.get()) do
        if sidebar_pickers[picker.opts.source] and picker.list.win.buf == ev.buf then
          return close_sidebars(picker.opts.source)
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
