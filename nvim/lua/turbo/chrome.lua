-- Turbo Pascal screen furniture: the bottom hint line, "═[■]═ file ═ 1 ═"
-- window title frames, and the About dialog.
local M = {}
local api = vim.api

-- status line ---------------------------------------------------------------

local hints = {
  { "F1", "Help" }, { "F2", "Save" }, { "F3", "Open" },
  { "F9", "Make" }, { "Alt+F10", "Local menu" }, { "F10", "Menu" },
}

local modes = { i = "Insert", R = "Overwrite", v = "Block", V = "Block", ["\22"] = "Block", t = "Terminal", c = "Command" }

local function esc(s)
  return (s:gsub("%%", "%%%%"))
end

function M.statusline()
  local menu_hint = require("turbo.menubar").hint()
  if menu_hint then
    return "%#StatusLine# " .. esc(menu_hint)
  end
  local parts = { "%#StatusLine#" }
  for _, h in ipairs(hints) do
    table.insert(parts, (" %%#TurboStatusKey#%s%%#StatusLine# %s "):format(h[1], h[2]))
  end
  table.insert(parts, "%=")
  local reg = vim.fn.reg_recording()
  if reg ~= "" then
    table.insert(parts, "Recording @" .. reg .. " │ ")
  end
  local mode = modes[api.nvim_get_mode().mode:sub(1, 1)]
  if mode then
    table.insert(parts, mode .. " │ ")
  end
  table.insert(parts, "%{&modified ? '* ' : ''}%l:%c ")
  return table.concat(parts)
end

-- window title frame (winbar) -------------------------------------------------

local active_win

local function framed(win)
  if api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local bt = vim.bo[api.nvim_win_get_buf(win)].buftype
  return bt == "" or bt == "help"
end

function M.winbar()
  local win = vim.g.statusline_winid
  local width = api.nvim_win_get_width(win)
  local active = win == active_win
  local line = active and "═" or "─"
  local buf = api.nvim_win_get_buf(win)
  local name = api.nvim_buf_get_name(buf)
  name = name == "" and "NONAME00" or vim.fn.fnamemodify(name, ":~:.")
  local title = " " .. name .. " "
  local nr = " " .. api.nvim_win_get_number(win) .. " "
  local left = active and "═[%#TurboFrameIcon#■%#WinBar#]" or "──────"
  local right = active and (nr .. "═[%#TurboFrameIcon#↕%#WinBar#]═") or (nr .. "──────")
  local free = width - 6 - 7 - #nr - vim.fn.strdisplaywidth(title)
  if free < 2 then
    title = " " .. vim.fn.fnamemodify(name, ":t") .. " "
    free = math.max(2, width - 6 - 7 - #nr - vim.fn.strdisplaywidth(title))
  end
  local l = math.floor(free / 2)
  return table.concat({ left, line:rep(l), esc(title), line:rep(free - l), right })
end

local function update(win)
  if api.nvim_win_is_valid(win) then
    vim.wo[win].winbar = framed(win) and "%!v:lua.require'turbo.chrome'.winbar()" or ""
  end
end

-- About dialog ---------------------------------------------------------------

function M.about()
  local v = vim.version()
  local body = {
    "",
    "Turbo Vim",
    "Version 7.0",
    "",
    "A tribute to Borland Turbo Pascal 7.0",
    "and the Turbo Vision IDE (1983-1992)",
    "",
    ("Neovim %d.%d.%d + LazyVim"):format(v.major, v.minor, v.patch),
    "",
    "Jacob Andresen <jacob.andresen@gmail.com>",
    "",
    "",
  }
  local width = 48
  local inner = width - 2
  local tl = math.floor((inner - 7) / 2)
  local lines = { "╔═[■]" .. ("═"):rep(tl - 4) .. " About " .. ("═"):rep(inner - 7 - tl) .. "╗" }
  for _, text in ipairs(body) do
    local pad = width - 2 - vim.fn.strdisplaywidth(text)
    local l = math.floor(pad / 2)
    table.insert(lines, "║" .. (" "):rep(l) .. text .. (" "):rep(pad - l) .. "║")
  end
  local button = "   OK   "
  local bpad = math.floor((width - 2 - #button) / 2)
  lines[#lines] = "║" .. (" "):rep(bpad) .. button .. " " .. (" "):rep(width - 3 - bpad - #button) .. "║"
  table.insert(lines, "║" .. (" "):rep(bpad + 1) .. ("▀"):rep(#button) .. (" "):rep(width - 3 - bpad - #button) .. "║")
  table.insert(lines, "╚" .. ("═"):rep(width - 2) .. "╝")
  local height = #lines

  local row = math.floor((vim.o.lines - height) / 2) - 1
  local col = math.floor((vim.o.columns - width) / 2)
  local sbuf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(sbuf, 0, -1, false, vim.fn["repeat"]({ (" "):rep(width) }, height))
  local shadow = api.nvim_open_win(sbuf, false, {
    relative = "editor", row = row + 1, col = col + 2, width = width, height = height,
    style = "minimal", focusable = false, zindex = 249, border = "none",
  })
  vim.wo[shadow].winhighlight = "Normal:TurboShadow"
  vim.wo[shadow].winblend = 40

  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local win = api.nvim_open_win(buf, true, {
    relative = "editor", row = row, col = col, width = width, height = height,
    style = "minimal", zindex = 250, border = "none",
  })
  vim.wo[win].winhighlight = "Normal:TurboDialog"

  local ns = api.nvim_create_namespace("turbo_about")
  local frame = #"║"
  for r = 0, height - 1 do
    local line = lines[r + 1]
    api.nvim_buf_set_extmark(buf, ns, r, 0, { end_col = #line, hl_group = "TurboDialogFrame" })
    if r > 0 and r < height - 1 then
      api.nvim_buf_set_extmark(buf, ns, r, frame, { end_col = #line - frame, hl_group = "TurboDialog", priority = 150 })
    end
  end
  local title_start = lines[1]:find("[", 1, true) - 1
  api.nvim_buf_set_extmark(buf, ns, 0, title_start + 1, { end_col = title_start + 1 + #"■", hl_group = "TurboFrameIcon", priority = 160 })
  local t = lines[1]:find(" About ", 1, true) - 1
  api.nvim_buf_set_extmark(buf, ns, 0, t, { end_col = t + 7, hl_group = "TurboDialogTitle", priority = 160 })
  for r, text in ipairs(body) do
    if text == "Turbo Vim" then
      local s = lines[r + 1]:find("Turbo Vim", 1, true) - 1
      api.nvim_buf_set_extmark(buf, ns, r, s, { end_col = s + #text, hl_group = "TurboDialogTitle", priority = 160 })
    end
  end
  local brow = height - 3
  local bstart = frame + bpad
  api.nvim_buf_set_extmark(buf, ns, brow, bstart, { end_col = bstart + #button, hl_group = "TurboButton", priority = 160 })
  api.nvim_buf_set_extmark(buf, ns, brow, bstart + #button, { end_col = bstart + #button + 1, hl_group = "TurboButtonShadow", priority = 160 })
  api.nvim_buf_set_extmark(buf, ns, brow + 1, bstart + 1, { end_col = bstart + 1 + #("▀"):rep(#button), hl_group = "TurboButtonShadow", priority = 160 })
  api.nvim_win_set_cursor(win, { brow + 1, bstart + 3 })

  local function close()
    for _, w in ipairs({ win, shadow }) do
      if api.nvim_win_is_valid(w) then
        api.nvim_win_close(w, true)
      end
    end
  end
  for _, lhs in ipairs({ "<CR>", "<Esc>", "<Space>", "q", "o", "O", "<LeftMouse>" }) do
    vim.keymap.set("n", lhs, close, { buffer = buf, nowait = true })
  end
  api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = close })
end

function M.setup()
  vim.o.laststatus = 3
  vim.o.statusline = "%!v:lua.require'turbo.chrome'.statusline()"
  vim.opt.fillchars:append({ vert = "║", horiz = "═", horizup = "╩", horizdown = "╦", vertleft = "╣", vertright = "╠", verthoriz = "╬" })

  local group = api.nvim_create_augroup("turbo_chrome", { clear = true })
  api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "FileType", "TermOpen" }, {
    group = group,
    callback = function()
      local win = api.nvim_get_current_win()
      if api.nvim_win_get_config(win).relative == "" then
        active_win = win
      end
      update(win)
    end,
  })
  -- the startup screen hides the tabline and statusline; TP always shows the
  -- menu bar and hint line
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = "SnacksDashboardOpened",
    callback = function()
      vim.o.showtabline, vim.o.laststatus = 2, 3
    end,
  })
  api.nvim_create_autocmd({ "ModeChanged", "RecordingEnter", "RecordingLeave" }, {
    group = group,
    callback = function() vim.cmd.redrawstatus() end,
  })
  for _, win in ipairs(api.nvim_list_wins()) do
    update(win)
  end
  active_win = api.nvim_get_current_win()
end

return M
