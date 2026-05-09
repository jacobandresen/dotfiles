local M = {}

function M.setup()
  local hls = {
    TurboBar             = { bg = "#008080", fg = "#ffffff" },
    TurboItem            = { bg = "#008080", fg = "#ffffff" },
    TurboShortcut        = { bg = "#008080", fg = "#ffff55", bold = true },
    TurboItemSel         = { bg = "#aaaaaa", fg = "#000000" },
    TurboShortcutSel     = { bg = "#aaaaaa", fg = "#000000", bold = true, underline = true },
    TurboDropdown        = { bg = "#aaaaaa", fg = "#000000" },
    TurboDropdownBorder  = { bg = "#aaaaaa", fg = "#555555" },
    TurboDropdownSel     = { bg = "#000080", fg = "#ffffff" },
    TurboDropdownKey     = { bg = "#aaaaaa", fg = "#cc0000", bold = true },
    TurboDropdownKeySel  = { bg = "#000080", fg = "#ffff55", bold = true },
    TurboDropdownHint    = { bg = "#aaaaaa", fg = "#444444" },
    TurboDropdownHintSel = { bg = "#000080", fg = "#88aaff" },
    TurboDropdownSep     = { bg = "#aaaaaa", fg = "#666666" },
  }
  for name, attrs in pairs(hls) do
    vim.api.nvim_set_hl(0, name, attrs)
  end
end

return M
