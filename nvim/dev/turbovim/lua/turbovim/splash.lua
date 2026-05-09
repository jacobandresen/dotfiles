local M = {}

-- ANSI Shadow block-letter art for TURBOVIM.
-- All lines are exactly 66 display columns wide (1 cell per char assumed).
local logo = {
  "████████╗██╗   ██╗██████╗ ██████╗  ██████╗ ██╗   ██╗██╗███╗   ███╗",
  "╚══██╔══╝██║   ██║██╔══██╗██╔══██╗██╔═══██╗██║   ██║██║████╗ ████║",
  "   ██║   ██║   ██║██████╔╝██████╔╝██║   ██║╚██╗ ██╔╝██║██╔████╔██║",
  "   ██║   ██║   ██║██╔══██╗██╔══██╗██║   ██║ ╚████╔╝ ██║██║╚██╔╝██║",
  "   ██║   ╚██████╔╝██║  ██║██████╔╝╚██████╔╝  ╚═══╝  ██║██║ ╚═╝ ██║",
  "   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═════╝  ╚═════╝          ╚═╝╚═╝     ╚═╝",
}
local LOGO_W  = 66  -- known display width; avoids strdisplaywidth mis-counting wide chars
local tagline = "The Turbo Pascal experience — in Neovim."

local function pad_center(str, win_w)
  local str_w = #str  -- tagline is ASCII, safe to use byte length
  return string.rep(" ", math.max(0, math.floor((win_w - str_w) / 2))) .. str
end

function M.show()
  local win_w = math.min(LOGO_W + 4, vim.o.columns - 2)
  local logo_pad = math.max(0, math.floor((win_w - LOGO_W) / 2))

  local lines = { "" }
  for _, line in ipairs(logo) do
    lines[#lines + 1] = string.rep(" ", logo_pad) .. line
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = pad_center(tagline, win_w)
  lines[#lines + 1] = ""
  local win_h = #lines

  local screen_h = math.max(1, vim.o.lines - vim.o.cmdheight - 1)
  local row = math.max(0, math.floor((screen_h - win_h) / 2))
  local col = math.max(0, math.floor((vim.o.columns - win_w) / 2))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden  = "wipe"

  local ok, win = pcall(vim.api.nvim_open_win, buf, true, {
    relative = "editor",
    row      = row,
    col      = col,
    width    = win_w,
    height   = win_h,
    style    = "minimal",
    border   = "rounded",
    zindex   = 100,
  })
  if not ok then
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.notify("TurboVim: could not open splash (" .. tostring(win) .. ")", vim.log.levels.WARN)
    return
  end

  vim.wo[win].winhl = "Normal:TurboDropdown,FloatBorder:TurboShortcut"

  local ns = vim.api.nvim_create_namespace("turbovim_splash")
  for i = 2, #logo + 1 do
    vim.api.nvim_buf_add_highlight(buf, ns, "TurboShortcut", i - 1, 0, -1)
  end
  vim.api.nvim_buf_add_highlight(buf, ns, "TurboItem", win_h - 2, 0, -1)

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "<Esc>",   close, opts)
  vim.keymap.set("n", "<CR>",    close, opts)
  vim.keymap.set("n", "<Space>", close, opts)
  vim.keymap.set("n", "q",       close, opts)

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer   = buf,
    once     = true,
    callback = close,
  })
end

return M
