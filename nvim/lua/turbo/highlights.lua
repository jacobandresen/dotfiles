-- The Turbo* groups (menu bar, hint line, dialogs, status messages, window
-- frame icon) for colour schemes other than colors/turbopascal.lua, which
-- defines them itself. Retrobox (the default) gets a hand-tuned Turbo Vision
-- look in its gruvbox tones, matching ../mc/skins/retrobox.ini; any other
-- scheme gets them derived from its Pmenu/StatusLine/float groups.
local M = {}

local retrobox = {
  bg = "#1c1c1c", bg2 = "#504945", gray = "#a89984", fg = "#ebdbb2", white = "#fbf1c7",
  red = "#cc241d", darkred = "#9d0006", green = "#b8bb26", olive = "#98971a",
  yellow = "#fabd2f", aqua = "#8ec07c", blue = "#076678", purple = "#8f3f71", lightred = "#fb5944",
}

local function palette_groups(c)
  return {
    -- menu bar, drop-downs and hint line: grey, red hotkeys, green selection
    TurboMenu = { fg = c.bg, bg = c.gray },
    TurboMenuKey = { fg = c.darkred, bg = c.gray, bold = true },
    TurboMenuSel = { fg = c.bg, bg = c.olive },
    TurboMenuSelKey = { fg = c.white, bg = c.olive, bold = true },
    TurboShadow = { fg = c.bg2, bg = "#000000" },
    StatusLine = { fg = c.bg, bg = c.gray },
    StatusLineNC = { fg = c.bg, bg = c.gray },
    TurboStatusKey = { fg = c.darkred, bg = c.gray, bold = true },
    -- window title frames
    WinBar = { fg = c.fg, bg = c.bg, bold = true },
    WinBarNC = { fg = c.gray, bg = c.bg },
    TurboFrameIcon = { fg = c.green, bg = c.bg },
    -- dialogs
    TurboDialog = { fg = c.bg, bg = c.gray },
    TurboDialogFrame = { fg = c.white, bg = c.gray },
    TurboDialogTitle = { fg = c.white, bg = c.gray, bold = true },
    TurboButton = { fg = c.white, bg = c.olive, bold = true },
    TurboButtonShadow = { fg = c.bg, bg = c.gray },
    -- status messages
    TurboStatusMsg = { fg = c.bg, bg = c.gray },
    TurboStatusMsgTitle = { fg = c.blue, bg = c.gray, bold = true },
    TurboStatusMsgDim = { fg = c.bg2, bg = c.gray },
    TurboStatusMsgIcon = { fg = c.darkred, bg = c.gray },
    TurboStatusMsgWarn = { fg = c.purple, bg = c.gray, bold = true },
    TurboStatusMsgError = { fg = c.white, bg = c.red },
    TurboStatusMsgErrorTitle = { fg = c.yellow, bg = c.red, bold = true },
    -- Docker explorer container states
    SnacksPickerDockerRunning = { fg = c.green },
    SnacksPickerDockerPaused = { fg = c.aqua },
    SnacksPickerDockerExited = { fg = c.gray },
    SnacksPickerDockerDead = { fg = c.lightred, bold = true },
    SnacksPickerToggleOnlyRunning = { fg = c.bg, bg = c.green },
  }
end

local function get(name)
  local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
  if hl.reverse then
    hl.fg, hl.bg = hl.bg, hl.fg
  end
  return hl
end

-- any other scheme: reuse its own popup menu, status line and float colours
local function derived_groups()
  local pmenu, sel, status, float = get("Pmenu"), get("PmenuSel"), get("StatusLine"), get("NormalFloat")
  local normal, err, ok = get("Normal"), get("DiagnosticError"), get("DiagnosticOk")
  pmenu.bg, float.bg = pmenu.bg or normal.bg, float.bg or pmenu.bg or normal.bg
  pmenu.fg, sel.bg = pmenu.fg or normal.fg, sel.bg or pmenu.bg
  local key = err.fg
  return {
    TurboMenu = { fg = pmenu.fg, bg = pmenu.bg },
    TurboMenuKey = { fg = key, bg = pmenu.bg, bold = true },
    TurboMenuSel = { fg = sel.fg or pmenu.fg, bg = sel.bg },
    TurboMenuSelKey = { fg = key, bg = sel.bg, bold = true },
    TurboShadow = { fg = pmenu.bg, bg = "#000000" },
    TurboStatusKey = { fg = key, bg = status.bg, bold = true },
    TurboFrameIcon = { fg = ok.fg, bg = get("WinBar").bg },
    TurboDialog = { fg = float.fg or normal.fg, bg = float.bg },
    TurboDialogFrame = { link = "FloatBorder" },
    TurboDialogTitle = { link = "FloatTitle" },
    TurboButton = { fg = sel.fg or pmenu.fg, bg = sel.bg, bold = true },
    TurboButtonShadow = { fg = normal.bg, bg = float.bg },
    TurboStatusMsg = { link = "TurboDialog" },
    TurboStatusMsgTitle = { fg = get("Title").fg, bg = float.bg, bold = true },
    TurboStatusMsgDim = { fg = get("Comment").fg, bg = float.bg },
    TurboStatusMsgIcon = { fg = key, bg = float.bg },
    TurboStatusMsgWarn = { fg = get("DiagnosticWarn").fg, bg = float.bg, bold = true },
    TurboStatusMsgError = { link = "ErrorMsg" },
    TurboStatusMsgErrorTitle = { link = "ErrorMsg" },
    SnacksPickerDockerRunning = { link = "DiagnosticOk" },
    SnacksPickerDockerPaused = { link = "DiagnosticInfo" },
    SnacksPickerDockerExited = { link = "Comment" },
    SnacksPickerDockerDead = { link = "DiagnosticError" },
    SnacksPickerToggleOnlyRunning = { link = "PmenuSel" },
  }
end

function M.apply()
  local name = vim.g.colors_name
  if name == "turbopascal" then
    return
  end
  local groups = (name == "retrobox" and vim.o.background == "dark") and palette_groups(retrobox) or derived_groups()
  for group, spec in pairs(groups) do
    vim.api.nvim_set_hl(0, group, spec)
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("turbo_highlights", { clear = true }),
    callback = M.apply,
  })
  if vim.g.colors_name then
    M.apply()
  end
end

return M
