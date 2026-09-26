-- Turbo Vision style menu bar: drawn in the tabline, drop-downs are floating
-- windows with a box frame, a shadow, red hotkey letters and a green bar.
-- Menu contents live in turbo/menus.lua.
--
-- Item fields: label ("~N~ew": the letter between tildes is the hotkey),
-- key (shortcut text shown on the right), hint (status line text),
-- action (function(ctx)). A bare "-" is a separator. ctx.visual is true when
-- the menu was opened from Visual mode; the selection is then in '< and '>.
local M = {}

local ns = vim.api.nvim_create_namespace("turbo_menu")
local api = vim.api

M.menus = {} -- { { title = "~F~ile", items = {...} or function() } }
local open_level -- the open drop-down, if any
local ctx = { visual = false, win = nil }
local active_menu = nil -- index into M.menus while its drop-down is open
local last_menu = 2 -- F10 reopens the last used menu (default File)

-- "Save ~a~s" -> "Save as", "a", 5 (0-based char index of the hotkey)
local function parse(label)
  local s, key = label:match("^(.-)~(.)~")
  local text = label:gsub("~", "")
  if not s then
    return text, nil, nil
  end
  return text, key:lower(), vim.fn.strchars(s)
end

-- tabline ------------------------------------------------------------------

-- column (0-based) where each title starts, for placing its drop-down
local title_cols = {}

function M.tabline()
  local parts = { "%#TurboMenu# " }
  local col = 1
  for i, menu in ipairs(M.menus) do
    local text, _, hot = parse(menu.title)
    local sel = i == active_menu
    local base = sel and "%#TurboMenuSel#" or "%#TurboMenu#"
    local key = sel and "%#TurboMenuSelKey#" or "%#TurboMenuKey#"
    title_cols[i] = col
    local s = { base, " " }
    for ci, ch in ipairs(vim.fn.split(text, "\\zs")) do
      table.insert(s, ci - 1 == hot and (key .. ch .. base) or ch)
    end
    table.insert(s, " ")
    table.insert(parts, ("%%%d@v:lua.TurboMenuClick@%s%%X"):format(i, table.concat(s)))
    col = col + vim.fn.strdisplaywidth(text) + 2
  end
  table.insert(parts, "%#TurboMenu#%=")
  return table.concat(parts)
end

function _G.TurboMenuClick(idx)
  vim.schedule(function()
    if active_menu == idx then
      M.close()
    else
      M.open(idx)
    end
  end)
end

-- drop-downs -----------------------------------------------------------------

local function render(level)
  local buf = level.buf
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local left = #"│"
  for i, item in ipairs(level.items) do
    if item ~= "-" then
      local line = api.nvim_buf_get_lines(buf, i, i + 1, false)[1] -- row 0 is the frame
      local sel = i == level.sel
      api.nvim_buf_set_extmark(buf, ns, i, left, {
        end_col = #line - #"│", hl_group = sel and "TurboMenuSel" or "TurboMenu", priority = 100,
      })
      local text, _, hot = parse(item.label)
      if hot then
        local start = left + #" " + #vim.fn.strcharpart(text, 0, hot)
        api.nvim_buf_set_extmark(buf, ns, i, start, {
          end_col = start + #vim.fn.strcharpart(text, hot, 1),
          hl_group = sel and "TurboMenuSelKey" or "TurboMenuKey",
          priority = 110,
        })
      end
    end
  end
  api.nvim_win_set_cursor(level.win, { level.sel + 1, left + 1 })
  vim.cmd.redrawstatus()
  vim.cmd.redrawtabline()
end

function M.close()
  local level = open_level
  open_level, active_menu = nil, nil
  if level then
    for _, w in ipairs({ level.win, level.shadow }) do
      if api.nvim_win_is_valid(w) then
        api.nvim_win_close(w, true)
      end
    end
  end
  if ctx.win and api.nvim_win_is_valid(ctx.win) then
    api.nvim_set_current_win(ctx.win)
  end
  vim.cmd.redrawtabline()
  vim.cmd.redrawstatus()
end

-- status line hint for the highlighted item
function M.hint()
  local item = open_level and open_level.items[open_level.sel]
  return item and item ~= "-" and item.hint or nil
end

local function move(level, dir)
  local n = #level.items
  local i = level.sel
  for _ = 1, n do
    i = (i - 1 + dir) % n + 1
    if level.items[i] ~= "-" then
      level.sel = i
      break
    end
  end
  render(level)
end

local function activate(level, i)
  local item = level.items[i or level.sel]
  if not item or item == "-" then
    return
  end
  local context = vim.deepcopy(ctx)
  M.close()
  vim.schedule(function() item.action(context) end)
end

-- Left/Right move along the menu bar (not for the local menu)
local function switch(dir)
  if active_menu then
    M.open((active_menu - 1 + dir) % #M.menus + 1, { keep_ctx = true })
  end
end

-- letters are hotkeys first; j/k/h/l/q only navigate when no item uses them
local function on_key(level, key)
  for i, item in ipairs(level.items) do
    if item ~= "-" and select(2, parse(item.label)) == key then
      return activate(level, i)
    end
  end
  if key == "j" or key == "k" then
    move(level, key == "j" and 1 or -1)
  elseif key == "h" or key == "l" then
    switch(key == "l" and 1 or -1)
  elseif key == "q" then
    M.close()
  end
end

local function on_mouse(level)
  local pos = vim.fn.getmousepos()
  if pos.winid == level.win then
    local i = pos.line - 1
    if level.items[i] and level.items[i] ~= "-" then
      level.sel = i
      render(level)
      activate(level, i)
    end
    return
  end
  if pos.screenrow == 1 then
    for idx = #M.menus, 1, -1 do
      if pos.screencol - 1 >= title_cols[idx] then
        return idx == active_menu and M.close() or M.open(idx, { keep_ctx = true })
      end
    end
  end
  M.close()
end

local function open_dropdown(items, row, col)
  local labels, keys = {}, {}
  local wl, wk = 0, 0
  for i, item in ipairs(items) do
    if item ~= "-" then
      labels[i] = parse(item.label)
      keys[i] = item.key or ""
      wl = math.max(wl, vim.fn.strdisplaywidth(labels[i]))
      wk = math.max(wk, vim.fn.strdisplaywidth(keys[i]))
    end
  end
  local inner = wl + (wk > 0 and wk + 3 or 0) + 2
  local lines = { "┌" .. ("─"):rep(inner) .. "┐" }
  for i, item in ipairs(items) do
    if item == "-" then
      table.insert(lines, "├" .. ("─"):rep(inner) .. "┤")
    else
      local pad = inner - 2 - vim.fn.strdisplaywidth(labels[i]) - vim.fn.strdisplaywidth(keys[i])
      table.insert(lines, "│ " .. labels[i] .. (" "):rep(pad) .. keys[i] .. " │")
    end
  end
  table.insert(lines, "└" .. ("─"):rep(inner) .. "┘")

  local width, height = inner + 2, #lines
  col = math.max(0, math.min(col, vim.o.columns - width - 2))

  local sbuf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(sbuf, 0, -1, false, vim.fn["repeat"]({ (" "):rep(width) }, height))
  local shadow = api.nvim_open_win(sbuf, false, {
    relative = "editor", row = row + 1, col = col + 2, width = width, height = height,
    style = "minimal", focusable = false, zindex = 199, border = "none",
  })
  vim.wo[shadow].winhighlight = "Normal:TurboShadow"
  vim.wo[shadow].winblend = 40 -- the shadow is meant to show what's beneath

  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local win = api.nvim_open_win(buf, true, {
    relative = "editor", row = row, col = col, width = width, height = height,
    style = "minimal", zindex = 200, border = "none",
  })
  vim.wo[win].winhighlight = "Normal:TurboMenu"

  local level = { items = items, buf = buf, win = win, shadow = shadow, sel = 0 }
  open_level = level
  move(level, 1)

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true })
  end
  map("<Down>", function() move(level, 1) end)
  map("<Up>", function() move(level, -1) end)
  map("<Home>", function() level.sel = 0 move(level, 1) end)
  map("<End>", function() level.sel = #items + 1 move(level, -1) end)
  map("<CR>", function() activate(level) end)
  map("<Space>", function() activate(level) end)
  map("<Esc>", M.close)
  map("<F10>", M.close)
  map("<Left>", function() switch(-1) end)
  map("<Right>", function() switch(1) end)
  map("<LeftMouse>", function() on_mouse(level) end)
  for b = ("a"):byte(), ("z"):byte() do
    local ch = string.char(b)
    map(ch, function() on_key(level, ch) end)
    map(ch:upper(), function() on_key(level, ch) end)
  end
  for d = 0, 9 do
    map(tostring(d), function() on_key(level, tostring(d)) end)
  end

  -- clicking or jumping elsewhere closes the menu
  api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if open_level == level and api.nvim_get_current_win() ~= level.win then
          M.close()
        end
      end)
    end,
  })
end

local function save_ctx()
  local mode = api.nvim_get_mode().mode
  ctx.visual = mode:match("^[vV\22]") ~= nil
  if ctx.visual then
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  elseif mode:match("^i") then
    vim.cmd.stopinsert()
  end
  ctx.win = api.nvim_get_current_win()
end

---@param idx integer menu index
---@param opts? { keep_ctx?: boolean }
function M.open(idx, opts)
  if not (opts and opts.keep_ctx) then
    save_ctx()
  end
  M.close()
  active_menu, last_menu = idx, idx
  vim.cmd.redrawtabline()
  local items = M.menus[idx].items
  open_dropdown(type(items) == "function" and items() or items, 1, title_cols[idx] or 1)
end

-- context ("local") menu at the cursor, like TP's Alt+F10 / right click
function M.popup(items)
  save_ctx()
  M.close()
  local pos = vim.fn.screenpos(0, vim.fn.line("."), vim.fn.col("."))
  local height = #items + 2
  local row = pos.row -- 1-based screen row = the line below the cursor
  if row + height > vim.o.lines - 2 then
    row = math.max(1, pos.row - height - 1)
  end
  open_dropdown(items, row, math.max(0, pos.col - 1))
end

function M.open_last()
  M.open(last_menu)
end

-- open a menu by its hotkey letter, e.g. "f" for File
function M.open_key(key)
  for i, menu in ipairs(M.menus) do
    if select(2, parse(menu.title)) == key then
      return M.open(i)
    end
  end
end

---@param menus table[]
function M.setup(menus)
  M.menus = menus
  M.tabline() -- compute title columns
  vim.o.showtabline = 2
  vim.o.tabline = "%!v:lua.require'turbo.menubar'.tabline()"
end

return M
