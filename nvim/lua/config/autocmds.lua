-- silently update plugins on startup (no notification, no UI window).
-- LazyVim sources this file at VeryLazy (or earlier when opening a file), so
-- a nested VeryLazy autocmd wouldn't reliably fire - just defer the call.
vim.schedule(function()
  require("lazy").update({ show = false, wait = false })
end)

-- auto-refresh log/jsonl files every 2 seconds
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*.log", "*.jsonl" },
  callback = function(args)
    local buf = args.buf
    if vim.b[buf].log_refresh then
      return -- already polling (e.g. after :e)
    end
    vim.b[buf].log_refresh = true
    vim.opt_local.autoread = true
    local timer = vim.uv.new_timer()
    timer:start(2000, 2000, vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        timer:stop()
        timer:close()
        return
      end
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("checktime")
      end)
    end))
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
      buffer = buf,
      once = true,
      callback = function()
        timer:stop()
        timer:close()
      end,
    })
  end,
})

-- <leader>cF next to LazyVim's <leader>ca (code action), only where LSP
-- offers code actions
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client and client:supports_method("textDocument/codeAction") then
      vim.keymap.set("n", "<leader>cF", require("util.lsp").fix_all, { buffer = args.buf, desc = "Fix All Diagnostics" })
    end
  end,
})

-- only one sidebar at a time: the file explorer, the Docker explorer
-- (util/compose) or the Dadbod drawer - the one opened last stays open
local sidebar_pickers = { explorer = true, compose = true }

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
  group = vim.api.nvim_create_augroup("turbo_one_sidebar", { clear = true }),
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
