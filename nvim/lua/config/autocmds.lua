-- One poller for visible logs; hidden buffers refresh when displayed again.
local log_timer
local function visible_logs()
  local buffers = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.b[buf].log_refresh then buffers[buf] = true end
  end
  return buffers
end
local function check_logs()
  for buf in pairs(visible_logs()) do
    vim.api.nvim_buf_call(buf, function() vim.cmd("checktime " .. buf) end)
  end
end
local function stop_log_timer()
  if not log_timer then return end
  log_timer:stop()
  log_timer:close()
  log_timer = nil
end
local function sync_log_timer()
  if next(visible_logs()) then
    if not log_timer then
      log_timer = vim.uv.new_timer()
      log_timer:start(2000, 2000, vim.schedule_wrap(check_logs))
    end
  elseif log_timer then
    stop_log_timer()
  end
end
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*.log", "*.jsonl" },
  callback = function(args)
    vim.b[args.buf].log_refresh = true
    vim.bo[args.buf].autoread = true
    sync_log_timer()
  end,
})
vim.api.nvim_create_autocmd({ "BufWinEnter", "FocusGained" }, {
  callback = function()
    vim.schedule(function()
      sync_log_timer()
      check_logs()
    end)
  end,
})
vim.api.nvim_create_autocmd({ "BufWinLeave", "WinClosed", "BufDelete" }, {
  callback = function() vim.schedule(sync_log_timer) end,
})
vim.api.nvim_create_autocmd("VimLeavePre", {
  once = true,
  callback = stop_log_timer,
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

-- Dadbod opens a new query in a split when the dashboard is the only editing
-- window. Remove that startup page once the database query buffer is ready.
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("turbo_dbui_hide_dashboard", { clear = true }),
  pattern = "sql",
  callback = function(args)
    if not vim.b[args.buf].dbui_db_key_name then return end
    vim.schedule(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == "snacks_dashboard" then
          vim.api.nvim_win_close(win, true)
          if vim.api.nvim_buf_is_valid(buf) and vim.fn.bufwinid(buf) == -1 then
            vim.api.nvim_buf_delete(buf, { force = true })
          end
        end
      end
    end)
  end,
})

-- Agents edit files on disk from their terminal; pick the changes up when
-- focus comes back to a buffer.
vim.api.nvim_create_autocmd({ "FocusGained", "TermLeave", "BufEnter" }, {
  group = vim.api.nvim_create_augroup("turbo_agent_reload", { clear = true }),
  callback = function()
    if vim.fn.mode() ~= "c" and vim.bo.buftype == "" then vim.cmd("checktime") end
  end,
})
