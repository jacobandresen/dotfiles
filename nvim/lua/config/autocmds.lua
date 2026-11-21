vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*.log", "*.jsonl" },
  callback = function(args)
    vim.bo[args.buf].autoread = true
  end,
})

require("util.sidebars").setup()

-- Pick up changes made on disk when focus returns or a buffer is entered.
vim.api.nvim_create_autocmd({ "FocusGained", "TermLeave", "BufEnter" }, {
  group = vim.api.nvim_create_augroup("agent_reload", { clear = true }),
  callback = function()
    vim.schedule(function()
      if vim.fn.mode() ~= "c" and vim.bo.buftype == "" then vim.cmd("checktime") end
    end)
  end,
})
