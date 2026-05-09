local state = require("turbovim.state")
local M = {}

local ns = vim.api.nvim_create_namespace("turbovim_dropdown")

local function build_lines(menu)
  local max_label, max_hint = 0, 0
  for _, item in ipairs(menu.items) do
    if not item.sep then
      max_label = math.max(max_label, #item.label)
      max_hint  = math.max(max_hint,  #(item.hint or ""))
    end
  end

  -- inner_width = " " + label_col + gap + hint_col + " "
  local inner_width = max_label + (max_hint > 0 and max_hint + 2 or 0) + 2
  inner_width = math.max(inner_width, 22)

  local lines      = {}
  local items_map  = {}

  for _, item in ipairs(menu.items) do
    if item.sep then
      lines[#lines + 1]     = string.rep("─", inner_width)
      items_map[#items_map + 1] = false
    else
      local hint    = item.hint or ""
      local gap     = inner_width - 2 - #item.label - #hint
      if max_hint > 0 and hint == "" then
        gap = inner_width - 2 - #item.label
      end
      local line
      if hint ~= "" then
        line = " " .. item.label .. string.rep(" ", gap) .. hint .. " "
      else
        line = " " .. item.label .. string.rep(" ", gap) .. " "
      end
      lines[#lines + 1]     = line
      items_map[#items_map + 1] = item
    end
  end

  return lines, items_map, inner_width
end

local function apply_hl(buf, menu, items_map, lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  for i, item in ipairs(menu.items) do
    local row = i - 1
    if item.sep then
      vim.api.nvim_buf_add_highlight(buf, ns, "TurboDropdownSep", row, 0, -1)
    else
      local sel      = i == state.dropdown_idx
      local hl_bg    = sel and "TurboDropdownSel"     or "TurboDropdown"
      local hl_key   = sel and "TurboDropdownKeySel"  or "TurboDropdownKey"
      local hl_hint  = sel and "TurboDropdownHintSel" or "TurboDropdownHint"

      vim.api.nvim_buf_add_highlight(buf, ns, hl_bg,  row, 0, -1)
      vim.api.nvim_buf_add_highlight(buf, ns, hl_key, row, 1, 2)  -- shortcut letter

      local hint = (items_map[i] and items_map[i].hint) or ""
      if hint ~= "" then
        local line      = lines[i]
        local hint_start = #line - #hint - 1
        vim.api.nvim_buf_add_highlight(buf, ns, hl_hint, row, hint_start, hint_start + #hint)
      end
    end
  end
end

function M.open()
  local menu                = state.menus[state.item_idx]
  local lines, items_map, w = build_lines(menu)

  local first = 1
  for i, v in ipairs(items_map) do
    if v then first = i; break end
  end
  state.dropdown_idx   = first
  state.dropdown_items = items_map
  state.dropdown_lines = lines
  state.dropdown_menu  = menu

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, false, {
    relative  = "editor",
    row       = 1,
    col       = state.item_cols[state.item_idx] or 0,
    width     = w,
    height    = #lines,
    style     = "minimal",
    border    = "single",
    focusable = false,
    zindex    = 50,
  })
  vim.wo[win].winhl = "Normal:TurboDropdown,FloatBorder:TurboDropdownBorder"

  state.dropdown_buf = buf
  state.dropdown_win = win

  apply_hl(buf, menu, items_map, lines)
end

function M.refresh_hl()
  if not state.dropdown_buf then return end
  apply_hl(state.dropdown_buf, state.dropdown_menu, state.dropdown_items, state.dropdown_lines)
end

function M.move(dir)
  local items = state.dropdown_items
  local idx   = state.dropdown_idx

  if dir > 0 then
    for i = idx + 1, #items do
      if items[i] then state.dropdown_idx = i; break end
    end
  else
    for i = idx - 1, 1, -1 do
      if items[i] then state.dropdown_idx = i; break end
    end
  end

  M.refresh_hl()
end

function M.execute()
  local item = state.dropdown_items and state.dropdown_items[state.dropdown_idx]
  M.close()
  require("turbovim.keymaps").deactivate()
  if item and item.action then
    vim.schedule(item.action)
  end
end

function M.close()
  if state.dropdown_win and vim.api.nvim_win_is_valid(state.dropdown_win) then
    vim.api.nvim_win_close(state.dropdown_win, true)
  end
  if state.dropdown_buf and vim.api.nvim_buf_is_valid(state.dropdown_buf) then
    vim.api.nvim_buf_delete(state.dropdown_buf, { force = true })
  end
  state.dropdown_win  = nil
  state.dropdown_buf  = nil
  state.dropdown_items = nil
  state.dropdown_lines = nil
  state.dropdown_menu  = nil
end

return M
