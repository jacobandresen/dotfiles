-- Turbo Vim: Neovim dressed as the Borland Turbo Pascal 7.0 IDE.
--   colors/turbopascal.lua  EGA palette
--   turbo/menubar.lua       menu bar + drop-downs
--   turbo/menus.lua         the TP7 menu tree (+ AI menu)
--   turbo/chrome.lua        hint line, window frames, About dialog
-- Debugger F-keys (F4, F7, F8, Ctrl+F2, Ctrl+F9, ...) live in plugins/dap.lua.
local M = {}

-- UI options; called from options.lua so they're in place before first draw
function M.setup()
  require("turbo.menubar").setup(require("turbo.menus").menus)
  require("turbo.chrome").setup()
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

function M.local_menu()
  require("turbo.menubar").popup(require("turbo.menus").local_menu)
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

  -- menus: F10 reopens the last one, Alt+Space the ≡ menu, Alt+letter a
  -- named one (Alt+A is the AI menu, Alt+B the DB menu), Alt+F10 / right click the local menu
  map({ "n", "x", "i" }, "<F10>", menubar.open_last, { desc = "Menu" })
  map({ "n", "x" }, "<M-Space>", function() menubar.open(1) end, { desc = "≡ Menu" })
  for _, key in ipairs({ "f", "e", "s", "r", "c", "d", "t", "o", "w", "a", "b", "h" }) do
    map({ "n", "x" }, "<M-" .. key .. ">", function() menubar.open_key(key) end, { desc = "Menu" })
  end
  map({ "n", "x" }, "<M-F10>", M.local_menu, { desc = "Local Menu" })
  map("n", "<RightMouse>", "<LeftMouse><cmd>lua require('turbo').local_menu()<cr>", { desc = "Local Menu" })

  -- File
  map({ "n", "x", "i" }, "<F2>", "<cmd>write<cr>", { desc = "Save" })
  map("n", "<F3>", function() LazyVim.pick("files")() end, { desc = "Open" })
  map("n", "<M-x>", "<cmd>confirm qall<cr>", { desc = "Exit" })

  -- Edit (CUA clipboard keys)
  map("n", "<M-BS>", "u", { desc = "Undo" })
  map("x", "<S-Del>", '"+d', { desc = "Cut" })
  map("x", "<C-Insert>", '"+y', { desc = "Copy" })
  map("x", "<C-Del>", '"_d', { desc = "Clear" })
  map("n", "<S-Insert>", '"+P', { desc = "Paste" })
  map("i", "<S-Insert>", "<C-r>+", { desc = "Paste" })

  -- Search / Tools
  map("n", "<S-F2>", function() LazyVim.pick("live_grep")() end, { desc = "Grep" })
  map("n", "<M-F8>", menus.qf("cnext"), { desc = "Go to next" })
  map("n", "<M-F7>", menus.qf("cprevious"), { desc = "Go to previous" })

  -- Compile
  map("n", "<F9>", menus.make, { desc = "Make" })

  -- Window
  map("n", "<F5>", function() Snacks.zen.zoom() end, { desc = "Zoom" })
  map("n", "<F6>", "<cmd>wincmd w<cr>", { desc = "Next window" })
  map("n", "<S-F6>", "<cmd>wincmd W<cr>", { desc = "Previous window" })
  map("n", "<M-F3>", function() Snacks.bufdelete() end, { desc = "Close" })
  map("n", "<M-0>", function() require("telescope.builtin").buffers({ sort_mru = true }) end, { desc = "Window list" })

  -- Help (plain F1 is Neovim's :help already)
  map("n", "<S-F1>", function() require("telescope.builtin").help_tags() end, { desc = "Help index" })
  map("n", "<C-F1>", function() pcall(vim.cmd.help, vim.fn.expand("<cword>")) end, { desc = "Topic search" })
end

return M
