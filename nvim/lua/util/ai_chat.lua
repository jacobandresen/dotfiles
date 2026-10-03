local M = {}
local api = vim.api
local origin

local function editor(win)
  if not win or not api.nvim_win_is_valid(win) then
    return false
  end
  local buf = api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= "codecompanion"
end

function M.setup()
  api.nvim_create_autocmd("WinLeave", {
    group = api.nvim_create_augroup("ai_chat_navigation", { clear = true }),
    callback = function()
      local win = api.nvim_get_current_win()
      if editor(win) then origin = win end
    end,
  })
end

function M.back()
  if vim.bo.filetype ~= "codecompanion" then
    return vim.notify("Back to code is available in AI chat")
  end
  if not editor(origin) then
    origin = nil
    for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
      if editor(win) then origin = win break end
    end
  end
  if not origin then
    return vim.notify("No code window is open", vim.log.levels.WARN)
  end
  vim.cmd.stopinsert()
  api.nvim_set_current_win(origin)
end

function M.add(visual)
  if not editor(api.nvim_get_current_win()) then
    return vim.notify("Select a code window before adding context", vim.log.levels.WARN)
  end
  origin = api.nvim_get_current_win()
  local buf = api.nvim_get_current_buf()
  local first = api.nvim_buf_get_mark(buf, "<")
  local last = api.nvim_buf_get_mark(buf, ">")
  -- CodeCompanion reads visual marks for ranged additions; preserve the user's selection.
  if not visual then
    local count = api.nvim_buf_line_count(buf)
    api.nvim_buf_set_mark(buf, "<", 1, 0, {})
    api.nvim_buf_set_mark(buf, ">", count, #api.nvim_buf_get_lines(buf, count - 1, count, false)[1], {})
  end
  local ok, err = pcall(require("codecompanion").add, { range = 2 })
  if not visual then
    api.nvim_buf_set_mark(buf, "<", first[1], first[2], {})
    api.nvim_buf_set_mark(buf, ">", last[1], last[2], {})
  end
  if not ok then return vim.notify(tostring(err), vim.log.levels.ERROR) end
  local chat = require("codecompanion").last_chat()
  if chat and chat.ui.winnr and api.nvim_win_is_valid(chat.ui.winnr) then
    api.nvim_set_current_win(chat.ui.winnr)
    local last_line = api.nvim_buf_line_count(chat.bufnr or api.nvim_win_get_buf(chat.ui.winnr))
    api.nvim_win_set_cursor(chat.ui.winnr, { last_line, 0 })
    vim.cmd.startinsert()
  end
end

return M
