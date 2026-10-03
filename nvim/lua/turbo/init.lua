-- Turbo Vim: Neovim dressed as the Borland Turbo Pascal 7.0 IDE.
--   colors/turbopascal.lua  EGA palette (the default scheme is retrobox)
--   turbo/highlights.lua    the Turbo chrome's colours under other schemes
--   turbo/menubar.lua       menu bar + drop-downs
--   turbo/menus.lua         the menu tree
--   turbo/chrome.lua        hint line, window frames, About dialog
-- Debugger F-keys (F4, F5, F7, F8 and their Shift variants) live in plugins/dap.lua.
--
-- Only plain and Shift+F-keys: GNOME and KDE grab Ctrl+F1-F4 (desktops),
-- Ctrl+F7-F10/F12 (Present Windows, desktop grid), Alt+F1-F10 (launcher,
-- run, window menu, close, move/resize/maximise) and Alt+Space (window menu,
-- KRunner) before the terminal sees them; F11/F12 are often terminal
-- fullscreen or drop-down terminal keys. TP's Ctrl/Alt+F-keys moved to Shift.
local M = {}

-- UI options; called from options.lua so they're in place before first draw
function M.setup()
  require("util.ai_wand").setup()
  require("turbo.menubar").setup(require("turbo.menus").menus)
  require("turbo.chrome").setup()
  require("turbo.highlights").setup()
end

-- Terminals without modifier-aware F-keys send xterm's F13-F60 instead
-- (Shift +12, Ctrl +24, Alt +48: Alt+F10 arrives as <F58>), so modified
-- F-keys are bound under both names.
function M.fkeys(lhs)
  local mod, n = lhs:match("^<([SCM])%-F(%d+)>$")
  if not mod then
    return { lhs }
  end
  return { lhs, ("<F%d>"):format(tonumber(n) + ({ S = 12, C = 24, M = 48 })[mod]) }
end

-- the same for lazy.nvim `keys` specs
function M.fkey_specs(specs)
  local out = {}
  for _, spec in ipairs(specs) do
    for _, lhs in ipairs(M.fkeys(spec[1])) do
      local s = vim.deepcopy(spec)
      s[1] = lhs
      table.insert(out, s)
    end
  end
  return out
end

-- items with a `when` function only show when it returns true
function M.local_menu()
  local items = vim.tbl_filter(function(item)
    return type(item) ~= "table" or not item.when or item.when()
  end, require("turbo.menus").local_menu)
  items = vim.tbl_map(function(item) return type(item) == "table" and item[1] == "-" and "-" or item end, items)
  require("turbo.menubar").popup(items)
end

-- TP key bindings; called from keymaps.lua
function M.keymaps()
  local function map(mode, lhs, rhs, opts)
    for _, l in ipairs(M.fkeys(lhs)) do
      vim.keymap.set(mode, l, rhs, opts)
    end
  end
  local menubar = require("turbo.menubar")
  local menus = require("turbo.menus")

  -- F10 reopens the last menu; Alt+letter opens a named menu.
  -- Shift+F10 / right click opens the local menu.
  map({ "n", "x", "i" }, "<F10>", menubar.open_last, { desc = "Menu" })
  for _, menu in ipairs(menus.menus) do
    local key = menu.title:match("~(.)~")
    if key then
      key = key:lower()
      map({ "n", "x" }, "<M-" .. key .. ">", function() menubar.open_key(key) end, { desc = "Menu" })
    end
  end
  map({ "n", "x" }, "<S-F10>", M.local_menu, { desc = "Local Menu" })
  map("n", "<RightMouse>", "<LeftMouse><cmd>lua require('turbo').local_menu()<cr>", { desc = "Local Menu" })

  -- File
  map({ "n", "x", "i" }, "<F2>", "<cmd>write<cr>", { desc = "Save" })
  map("n", "<F3>", function() LazyVim.pick("files")() end, { desc = "Open" })
  map("n", "<S-F3>", function() Snacks.bufdelete() end, { desc = "Close" })
  map("n", "<M-x>", "<cmd>confirm qall<cr>", { desc = "Exit" })

  -- Edit (CUA clipboard keys)
  map("n", "<M-BS>", "u", { desc = "Undo" })
  map("x", "<S-Del>", '"+d', { desc = "Cut" })
  map("x", "<C-Insert>", '"+y', { desc = "Copy" })
  map("x", "<C-Del>", '"_d', { desc = "Clear" })
  map("n", "<S-Insert>", '"+P', { desc = "Paste" })
  map("i", "<S-Insert>", "<C-r>+", { desc = "Paste" })

  -- Search
  map("n", "<S-F2>", function() LazyVim.pick("live_grep")() end, { desc = "Grep" })

  -- Build: F9 make, ]q/[q step through its messages (Trouble's list when open)
  map("n", "<F9>", menus.make, { desc = "Make" })
  map("n", "]q", menus.messages("next"), { desc = "Next message" })
  map("n", "[q", menus.messages("prev"), { desc = "Previous message" })

  -- Window
  map("n", "<F6>", "<cmd>wincmd w<cr>", { desc = "Next window" })
  map("n", "<S-F6>", "<cmd>wincmd W<cr>", { desc = "Previous window" })
  map("n", "<M-0>", function() require("telescope.builtin").buffers({ sort_mru = true }) end, { desc = "Window list" })

  -- Help (plain F1 is Neovim's :help already; Space s h is the index)
  map("n", "<S-F1>", menus.topic_search, { desc = "Topic search" })
end

return M
