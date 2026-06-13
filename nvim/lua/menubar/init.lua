-- Turbo Pascal / Borland-style menu bar for Neovim.
--
-- A global menu bar lives in the tabline (≡ File Edit ... Help) with red hotkey
-- letters on a light-gray bar, classic DOS-blue desktop below. Open a menu with
-- the mouse, with :TPMenu, or with <M-letter> (if your terminal forwards Alt --
-- see the note in lua/plugins/menubar.lua). Dropdowns are keyboard-navigable:
--   j/k or arrows  move      <CR>/<Space>  select      Esc/q  close
--   <Left>/<Right> switch menus           <letter>     jump to & run an item
--
-- The menu set is faithful to Turbo Pascal 7.0, wired to this config's actual
-- tooling (dap, oil, telescope, cargo/make).

local M = {}

-- Fixed CGA palette so the bar keeps its Turbo Pascal look regardless of the
-- active editor colorscheme.
local C = {
  black = "#000000",
  gray = "#aaaaaa", -- lightgray bar/menu background
  red = "#aa0000", -- hotkey letters
  green = "#00aa00", -- selection bar
  yellow = "#ffff55", -- hotkey on the selection bar
}

local function set_highlights()
  local hl = vim.api.nvim_set_hl
  hl(0, "TurboBar", { fg = C.black, bg = C.gray })
  hl(0, "TurboBarKey", { fg = C.red, bg = C.gray, bold = true })
  hl(0, "TurboBarSel", { fg = C.black, bg = C.green })
  hl(0, "TurboBarSelKey", { fg = C.yellow, bg = C.green, bold = true })
  hl(0, "TurboClock", { fg = C.black, bg = C.gray, bold = true })
  hl(0, "TurboMenu", { fg = C.black, bg = C.gray })
  hl(0, "TurboMenuKey", { fg = C.red, bg = C.gray, bold = true })
  hl(0, "TurboMenuSel", { fg = C.black, bg = C.green })
  hl(0, "TurboMenuSelKey", { fg = C.yellow, bg = C.green, bold = true })
  hl(0, "TurboMenuBorder", { fg = C.black, bg = C.gray })
end

--------------------------------------------------------------------------------
-- Actions used by menu items
--------------------------------------------------------------------------------

-- Run a shell command in a small terminal split (Compile/Run style).
local function term(cmd)
  vim.cmd("botright 12split | terminal " .. cmd)
  vim.cmd("startinsert")
end

-- Lazily require dap and call dap[name]() with optional args.
local function dap_call(name, ...)
  local args = { ... }
  return function()
    local ok, dap = pcall(require, "dap")
    if not ok then
      return vim.notify("nvim-dap not available", vim.log.levels.WARN)
    end
    dap[name](unpack(args))
  end
end

local function dapui_call(name)
  return function()
    local ok, dapui = pcall(require, "dapui")
    if not ok then
      return vim.notify("nvim-dap-ui not available", vim.log.levels.WARN)
    end
    dapui[name]()
  end
end

local function about()
  local msg = table.concat({
    "  ╔══════════════════════════════════╗",
    "  ║         Turbo Neovim  7.0        ║",
    "  ║   a Borland-style IDE for Neovim ║",
    "  ║                                  ║",
    "  ║     // wake up, neo...           ║",
    "  ╚══════════════════════════════════╝",
  }, "\n")
  vim.notify(msg, vim.log.levels.INFO, { title = "About" })
end

--------------------------------------------------------------------------------
-- Menu definitions. Each item: { "Label", key = "L", rhs = "hint", cmd|act }
-- A bare { sep = true } draws a separator.
--------------------------------------------------------------------------------

M.menus = {
  {
    name = "System",
    bar = "≡",
    items = {
      { "About Turbo Neovim", key = "A", act = about },
      { "Repaint desktop", key = "R", cmd = "mode" },
    },
  },
  {
    name = "File",
    bar = "File",
    key = "F",
    items = {
      { "New", key = "N", cmd = "enew" },
      { "Open...", key = "O", cmd = "Telescope find_files" },
      { "Open dir...", key = "D", cmd = "Oil" },
      { "Save", key = "S", rhs = "F2", cmd = "write" },
      { "Save as...", key = "a", act = function()
        vim.ui.input({ prompt = "Save as: ", default = vim.fn.expand("%:p"), completion = "file" }, function(p)
          if p and p ~= "" then vim.cmd("saveas " .. vim.fn.fnameescape(p)) end
        end)
      end },
      { sep = true },
      { "Change dir...", key = "C", act = function()
        vim.ui.input({ prompt = "Change dir: ", default = vim.fn.getcwd(), completion = "dir" }, function(p)
          if p and p ~= "" then vim.cmd("cd " .. vim.fn.fnameescape(p)) vim.notify("cwd: " .. p) end
        end)
      end },
      { sep = true },
      { "Quit", key = "Q", rhs = "Alt+X", cmd = "confirm qall" },
    },
  },
  {
    name = "Edit",
    bar = "Edit",
    key = "E",
    items = {
      { "Undo", key = "U", rhs = "u", cmd = "undo" },
      { "Redo", key = "R", rhs = "C-r", cmd = "redo" },
      { sep = true },
      { "Cut line", key = "t", cmd = 'normal! "+dd' },
      { "Copy line", key = "C", cmd = 'normal! "+yy' },
      { "Paste", key = "P", cmd = 'normal! "+p' },
      { sep = true },
      { "Select all", key = "S", cmd = "normal! ggVG" },
      { "Format buffer", key = "F", act = function() vim.lsp.buf.format({ async = true }) end },
    },
  },
  {
    name = "Search",
    bar = "Search",
    key = "S",
    items = {
      { "Find...", key = "F", rhs = "/", act = function() vim.api.nvim_feedkeys("/", "n", false) end },
      { "Replace...", key = "R", act = function()
        vim.api.nvim_feedkeys(":%s/", "n", false)
      end },
      { "Find next", key = "n", rhs = "n", cmd = "normal! n" },
      { "Find previous", key = "p", rhs = "N", cmd = "normal! N" },
      { sep = true },
      { "Find file...", key = "i", cmd = "Telescope find_files" },
      { "Grep in files...", key = "G", cmd = "Telescope live_grep" },
      { "Document symbols...", key = "D", cmd = "Telescope lsp_document_symbols" },
      { "Go to line...", key = "l", act = function()
        vim.ui.input({ prompt = "Go to line: " }, function(n)
          if n and tonumber(n) then vim.cmd("normal! " .. n .. "G") end
        end)
      end },
    },
  },
  {
    name = "Run",
    bar = "Run",
    key = "R",
    items = {
      { "Run / Continue", key = "R", rhs = "F5", act = dap_call("continue") },
      { "Step over", key = "O", rhs = "F10", act = dap_call("step_over") },
      { "Step into", key = "I", rhs = "F11", act = dap_call("step_into") },
      { "Step out", key = "t", rhs = "F12", act = dap_call("step_out") },
      { sep = true },
      { "Stop", key = "S", rhs = "F4", act = dap_call("terminate") },
      { "Restart", key = "e", rhs = "F9", act = dap_call("restart") },
    },
  },
  {
    name = "Compile",
    bar = "Compile",
    key = "C",
    items = {
      { "Make", key = "M", rhs = "F9", cmd = "make" },
      { "Cargo build", key = "B", act = function() term("cargo build") end },
      { "Cargo run", key = "R", act = function() term("cargo run") end },
      { "Cargo test", key = "T", act = function() term("cargo test") end },
      { sep = true },
      { "Quickfix list", key = "Q", cmd = "copen" },
    },
  },
  {
    name = "Debug",
    bar = "Debug",
    key = "D",
    items = {
      { "Toggle breakpoint", key = "B", rhs = "\\db", act = dap_call("toggle_breakpoint") },
      { "Conditional break...", key = "C", act = function()
        vim.ui.input({ prompt = "Condition: " }, function(c)
          if c and c ~= "" then require("dap").set_breakpoint(c) end
        end)
      end },
      { "Clear breakpoints", key = "l", rhs = "\\dC", act = dap_call("clear_breakpoints") },
      { sep = true },
      { "Evaluate", key = "E", rhs = "\\de", act = dapui_call("eval") },
      { "REPL", key = "R", rhs = "\\dr", act = dap_call("repl", "open") },
      { "Toggle debug UI", key = "U", rhs = "\\du", act = dapui_call("toggle") },
    },
  },
  {
    name = "Tools",
    bar = "Tools",
    key = "T",
    items = {
      { "File explorer", key = "E", rhs = "<leader>E", cmd = "Oil" },
      { "Find files", key = "F", cmd = "Telescope find_files" },
      { "Live grep", key = "G", cmd = "Telescope live_grep" },
      { "Buffers", key = "B", cmd = "Telescope buffers" },
      { "Terminal", key = "T", act = function() term("$SHELL") end },
      { sep = true },
      { "Diagnostics", key = "D", cmd = "Telescope diagnostics" },
      { "Plugins (Lazy)", key = "P", cmd = "Lazy" },
      { "Mason", key = "M", cmd = "Mason" },
    },
  },
  {
    name = "Options",
    bar = "Options",
    key = "O",
    items = {
      { "Toggle wrap", key = "W", cmd = "set wrap!" },
      { "Toggle line numbers", key = "N", cmd = "set number! relativenumber!" },
      { "Toggle spell", key = "S", cmd = "set spell!" },
      { sep = true },
      { "Colorscheme...", key = "C", cmd = "Telescope colorscheme" },
      { "Edit config", key = "E", cmd = "edit " .. vim.fn.stdpath("config") .. "/init.lua" },
      { "Plugin manager", key = "P", cmd = "Lazy" },
    },
  },
  {
    name = "Window",
    bar = "Window",
    key = "W",
    items = {
      { "Split horizontal", key = "H", cmd = "split" },
      { "Split vertical", key = "V", cmd = "vsplit" },
      { "Close window", key = "C", cmd = "close" },
      { "Close others", key = "O", cmd = "only" },
      { sep = true },
      { "Next window", key = "N", rhs = "C-w w", cmd = "wincmd w" },
      { sep = true },
      { "List buffers...", key = "L", cmd = "Telescope buffers" },
      { "Next buffer", key = "B", rhs = "]b", cmd = "bnext" },
      { "Previous buffer", key = "P", rhs = "[b", cmd = "bprevious" },
    },
  },
  {
    name = "Help",
    bar = "Help",
    key = "H",
    items = {
      { "Help contents", key = "H", cmd = "help" },
      { "Help index", key = "I", cmd = "help index" },
      { "Keymaps...", key = "K", cmd = "Telescope keymaps" },
      { "LazyVim docs", key = "L", cmd = "help lazyvim" },
      { sep = true },
      { "About Turbo Neovim", key = "A", act = about },
    },
  },
}

--------------------------------------------------------------------------------
-- Tabline rendering (the bar itself)
--------------------------------------------------------------------------------

local state = {
  open_index = nil, -- index of the menu whose dropdown is open
  win = nil,
  buf = nil,
  sel = 1,
  prev_win = nil,
  items = nil,
  width = 0,
  offsets = {}, -- display column where each bar segment starts
  augroup = nil,
  closing = false,
  timer = nil,
}

local NS = vim.api.nvim_create_namespace("turbo_menu")

-- Build a bar segment " Label " with the hotkey letter recolored.
local function bar_segment(text, key, base, keyhl)
  if not key then
    return "%#" .. base .. "#" .. text
  end
  local lc = text:lower()
  local s, e = lc:find(key:lower(), 1, true)
  if not s then
    return "%#" .. base .. "#" .. text
  end
  return table.concat({
    "%#" .. base .. "#" .. text:sub(1, s - 1),
    "%#" .. keyhl .. "#" .. text:sub(s, e),
    "%#" .. base .. "#" .. text:sub(e + 1),
  })
end

function _G.TurboMenu_tabline()
  local parts = {}
  local col = 0
  state.offsets = {}
  for i, menu in ipairs(M.menus) do
    local text = " " .. menu.bar .. " "
    state.offsets[i] = col
    local open = state.open_index == i
    local base = open and "TurboBarSel" or "TurboBar"
    local keyhl = open and "TurboBarSelKey" or "TurboBarKey"
    local seg = bar_segment(text, menu.key, base, keyhl)
    parts[#parts + 1] = string.format("%%%d@v:lua.TurboMenu_click@%s%%X", i, seg)
    col = col + vim.fn.strdisplaywidth(text)
  end
  parts[#parts + 1] = "%#TurboBar#%=%#TurboClock# " .. os.date("%H:%M:%S") .. " "
  return table.concat(parts)
end

function _G.TurboMenu_click(minwid)
  M.open(minwid)
  return ""
end

--------------------------------------------------------------------------------
-- Dropdown engine
--------------------------------------------------------------------------------

-- Render the dropdown buffer lines + highlights for the current selection.
local function render()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end
  local lines = {}
  for _, item in ipairs(state.items) do
    if item.sep then
      lines[#lines + 1] = string.rep("─", state.width)
    else
      local label = item[1]
      local rhs = item.rhs or ""
      -- width already reserves a 2-cell gap when any item has an rhs hint
      local pad = state.width - 1 - vim.fn.strdisplaywidth(label) - #rhs - 1
      if pad < 0 then pad = 0 end
      lines[#lines + 1] = " " .. label .. string.rep(" ", pad) .. rhs .. " "
    end
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
  for idx, item in ipairs(state.items) do
    local row = idx - 1
    local line = lines[idx]
    if not item.sep then
      local selected = idx == state.sel
      if selected then
        vim.api.nvim_buf_set_extmark(state.buf, NS, row, 0, {
          end_col = #line,
          hl_group = "TurboMenuSel",
          hl_eol = true,
        })
      end
      -- recolor the hotkey letter (yellow on the green selection bar, else red)
      if item.key then
        local label = item[1]
        local s = label:lower():find(item.key:lower(), 1, true)
        if s then
          local col = 1 + (s - 1) -- leading space + 0-based offset
          vim.api.nvim_buf_set_extmark(state.buf, NS, row, col, {
            end_col = col + #item.key,
            hl_group = selected and "TurboMenuSelKey" or "TurboMenuKey",
          })
        end
      end
    end
  end

  if vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_set_cursor, state.win, { state.sel, 0 })
  end
end

local function first_item()
  for i, item in ipairs(state.items) do
    if not item.sep then return i end
  end
  return 1
end

-- Move selection by dir (+1/-1), skipping separators and wrapping.
local function move(dir)
  local n = #state.items
  local i = state.sel
  for _ = 1, n do
    i = ((i - 1 + dir) % n) + 1
    if not state.items[i].sep then
      state.sel = i
      return render()
    end
  end
end

local function run_item(item)
  if not item then return end
  local ok, err = pcall(function()
    if item.cmd then
      vim.cmd(item.cmd)
    elseif item.act then
      item.act()
    end
  end)
  if not ok then
    vim.notify("Menu action failed: " .. tostring(err), vim.log.levels.ERROR)
  end
end

function M.close()
  if state.closing then return end
  state.closing = true
  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    state.augroup = nil
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  state.win, state.buf, state.items = nil, nil, nil
  state.open_index = nil
  state.closing = false
  pcall(vim.cmd, "redrawtabline")
end

local function select_current()
  local item = state.items and state.items[state.sel]
  if not item or item.sep then return end
  local prev = state.prev_win
  M.close()
  if prev and vim.api.nvim_win_is_valid(prev) then
    pcall(vim.api.nvim_set_current_win, prev)
  end
  vim.schedule(function() run_item(item) end)
end

local function hotkey(letter)
  for i, item in ipairs(state.items) do
    if not item.sep and item.key and item.key:lower() == letter:lower() then
      state.sel = i
      render()
      return select_current()
    end
  end
end

function M.open(index)
  if index < 1 or index > #M.menus then return end
  -- toggle off if the same menu is already open
  if state.open_index == index then return M.close() end

  -- When switching menus, the current window is the open dropdown (which close()
  -- destroys). Keep the original editor window so focus is restored correctly.
  local original = (state.open_index ~= nil) and state.prev_win or vim.api.nvim_get_current_win()
  M.close()
  state.prev_win = original
  state.open_index = index
  local menu = M.menus[index]
  state.items = menu.items

  -- width = widest "label  rhs" plus 2 padding spaces
  local lw, rw = 0, 0
  for _, item in ipairs(state.items) do
    if not item.sep then
      lw = math.max(lw, vim.fn.strdisplaywidth(item[1]))
      rw = math.max(rw, #(item.rhs or ""))
    end
  end
  state.width = 1 + lw + (rw > 0 and (2 + rw) or 0) + 1

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].filetype = "turbomenu"

  local col = state.offsets[index] or 0
  -- keep the dropdown on-screen
  col = math.min(col, math.max(0, vim.o.columns - state.width - 2))

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    row = 1,
    col = col,
    width = state.width,
    height = #state.items,
    style = "minimal",
    border = "single",
    zindex = 250,
    noautocmd = true,
  })
  vim.wo[state.win].winhighlight =
    "Normal:TurboMenu,FloatBorder:TurboMenuBorder,EndOfBuffer:TurboMenu"
  vim.wo[state.win].cursorline = false

  state.sel = first_item()
  render()
  pcall(vim.cmd, "redrawtabline")

  -- buffer-local keymaps
  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true, silent = true })
  end
  map("j", function() move(1) end)
  map("<Down>", function() move(1) end)
  map("k", function() move(-1) end)
  map("<Up>", function() move(-1) end)
  map("<CR>", select_current)
  map("<Space>", select_current)
  map("<Esc>", M.close)
  map("q", M.close)
  map("<Left>", function() M.open(index == 1 and #M.menus or index - 1) end)
  map("<Right>", function() M.open(index == #M.menus and 1 or index + 1) end)
  map("<LeftMouse>", function()
    local pos = vim.fn.getmousepos()
    if pos.winid == state.win and pos.line >= 1 and pos.line <= #state.items then
      if not state.items[pos.line].sep then
        state.sel = pos.line
        select_current()
      end
    else
      M.close()
    end
  end)
  -- hotkey letters
  for _, item in ipairs(state.items) do
    if not item.sep and item.key then
      local letter = item.key:lower()
      map(letter, function() hotkey(letter) end)
    end
  end

  -- auto-close when focus leaves the dropdown
  state.augroup = vim.api.nvim_create_augroup("TurboMenuActive", { clear = true })
  vim.api.nvim_create_autocmd("WinLeave", {
    group = state.augroup,
    buffer = state.buf,
    callback = function() M.close() end,
  })
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

function M.setup()
  set_highlights()
  vim.api.nvim_create_autocmd("ColorScheme", { callback = set_highlights })

  vim.o.showtabline = 2
  vim.o.tabline = "%!v:lua.TurboMenu_tabline()"

  -- Alt+<letter> to open menus (only works if the terminal forwards Meta keys).
  for i, menu in ipairs(M.menus) do
    if menu.key then
      vim.keymap.set("n", "<M-" .. menu.key:lower() .. ">", function() M.open(i) end,
        { silent = true, desc = "Menu: " .. menu.name })
    end
  end
  vim.keymap.set("n", "<M-Space>", function() M.open(1) end, { silent = true, desc = "Menu: System" })

  -- File explorer (Tools menu). Set here on VeryLazy so it overrides LazyVim's
  -- default <leader>E (Snacks explorer); this config uses Oil instead.
  vim.keymap.set("n", "<leader>E", "<cmd>Oil<cr>", { silent = true, desc = "File explorer (Oil)" })

  -- :TPMenu [name] -- reliable activator that works in any terminal.
  vim.api.nvim_create_user_command("TPMenu", function(o)
    if o.args ~= "" then
      for i, menu in ipairs(M.menus) do
        if menu.name:lower() == o.args:lower() then return M.open(i) end
      end
      vim.notify("No such menu: " .. o.args, vim.log.levels.WARN)
    else
      M.open(2) -- File
    end
  end, {
    nargs = "?",
    complete = function()
      local names = {}
      for _, menu in ipairs(M.menus) do names[#names + 1] = menu.name end
      return names
    end,
  })

  -- live clock in the bar
  if state.timer then pcall(function() state.timer:stop() end) end
  state.timer = vim.uv.new_timer()
  state.timer:start(1000, 1000, vim.schedule_wrap(function()
    pcall(vim.cmd, "redrawtabline")
  end))
end

-- exposed for debugging / tests
M._state = state

return M
