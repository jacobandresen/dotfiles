local state = require("turbovim.state")
local M = {}

-- Calculates the screen column where each menu item begins (0-indexed).
-- Called once at setup since labels are static.
function M.calc_cols()
  local cols = {}
  local col = 1  -- after the single leading space
  for i, menu in ipairs(state.menus) do
    cols[i] = col
    col = col + 1 + #menu.label + 1  -- " Label "
  end
  state.item_cols = cols
end

function M.render()
  local parts = { "%#TurboBar# " }

  for i, menu in ipairs(state.menus) do
    local sel = state.active and state.item_idx == i
    local bg   = sel and "TurboItemSel"     or "TurboBar"
    local fg_k = sel and "TurboShortcutSel" or "TurboShortcut"
    local fg_r = sel and "TurboItemSel"     or "TurboItem"

    parts[#parts + 1] = ("%%#%s# %%#%s#%s%%#%s#%s "):format(
      bg, fg_k, menu.label:sub(1, 1), fg_r, menu.label:sub(2)
    )
  end

  parts[#parts + 1] = "%#TurboBar#%="
  return table.concat(parts)
end

function M.refresh()
  vim.cmd("redrawtabline")
end

local function apply()
  vim.o.tabline     = "%!v:lua._turbovim_tabline()"
  vim.o.showtabline = 2
end

function M.setup()
  M.calc_cols()
  _G._turbovim_tabline = M.render

  -- Defer until after all plugins (including bufferline) have loaded,
  -- then re-apply on every ColorScheme so nothing can stomp it.
  vim.api.nvim_create_autocmd("VimEnter", {
    group    = vim.api.nvim_create_augroup("TurboVimBar", { clear = true }),
    once     = true,
    callback = apply,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group    = "TurboVimBar",
    callback = apply,
  })
end

return M
