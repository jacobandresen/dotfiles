local state = require("turbovim.state")
local M = {}

local active_maps = {}

local function nmap(key, fn)
  vim.keymap.set("n", key, fn, { nowait = true, silent = true })
  active_maps[#active_maps + 1] = key
end

function M.deactivate()
  state.active = false

  if state.dropdown_open then
    require("turbovim.dropdown").close()
    state.dropdown_open = false
  end

  for _, key in ipairs(active_maps) do
    pcall(vim.keymap.del, "n", key)
  end
  active_maps = {}

  require("turbovim.bar").refresh()
end

function M.activate()
  state.active = true

  local bar      = require("turbovim.bar")
  local dropdown = require("turbovim.dropdown")
  local n        = #state.menus

  nmap("<Right>", function()
    local was_open = state.dropdown_open
    if was_open then dropdown.close(); state.dropdown_open = false end
    state.item_idx = (state.item_idx % n) + 1
    if was_open then dropdown.open(); state.dropdown_open = true end
    bar.refresh()
  end)

  nmap("<Left>", function()
    local was_open = state.dropdown_open
    if was_open then dropdown.close(); state.dropdown_open = false end
    state.item_idx = ((state.item_idx - 2) % n) + 1
    if was_open then dropdown.open(); state.dropdown_open = true end
    bar.refresh()
  end)

  nmap("<Down>", function()
    if not state.dropdown_open then
      state.dropdown_open = true
      dropdown.open()
    else
      dropdown.move(1)
    end
    bar.refresh()
  end)

  nmap("<Up>", function()
    if state.dropdown_open then
      dropdown.move(-1)
      bar.refresh()
    end
  end)

  nmap("<CR>", function()
    if not state.dropdown_open then
      state.dropdown_open = true
      dropdown.open()
      bar.refresh()
    else
      dropdown.execute()
    end
  end)

  nmap("<Esc>", function()
    if state.dropdown_open then
      dropdown.close()
      state.dropdown_open = false
      bar.refresh()
    else
      M.deactivate()
    end
  end)

  bar.refresh()
end

function M.setup(config)
  vim.keymap.set("n", config.key, function()
    if state.active then
      M.deactivate()
    else
      M.activate()
    end
  end, { silent = true, desc = "TurboVim: toggle menu" })

  -- Alt+letter shortcuts jump directly to a menu and open its dropdown
  for i, menu in ipairs(state.menus) do
    vim.keymap.set("n", ("<M-%s>"):format(menu.key), function()
      local dropdown = require("turbovim.dropdown")
      local bar      = require("turbovim.bar")

      if state.dropdown_open then
        dropdown.close()
        state.dropdown_open = false
      end

      if not state.active then M.activate() end

      state.item_idx   = i
      state.dropdown_open = true
      dropdown.open()
      bar.refresh()
    end, { silent = true, desc = ("TurboVim: %s menu"):format(menu.label) })
  end
end

return M
