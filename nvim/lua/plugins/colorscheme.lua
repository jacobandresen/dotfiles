-- Commodore 64 theme for Neovim, matching the C64 wezterm colors. If
-- ~/.wezterm.lua sets a base16 color_scheme, follow that instead so the two stay
-- in sync; otherwise apply the custom C64 palette below.
local function get_wezterm_scheme()
  local f = io.open(vim.fn.expand("~/.wezterm.lua"), "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content:match('config%.color_scheme%s*=%s*"([^"]+)"')
end

local function wezterm_to_base16(scheme)
  if not scheme then return nil end
  local name = scheme:match("^(.-)%s*%(base16%)$") or scheme
  return "base16-" .. name:lower():gsub("%s+", "-")
end

local nvim_scheme = wezterm_to_base16(get_wezterm_scheme())

-- Commodore 64 (colodore VIC-II palette), brightened for legibility on the blue
-- screen -- the same colors as ~/.wezterm.lua.
local c64 = {
  base00 = "#2e2c9b", -- background (C64 blue screen)
  base01 = "#3835a6", -- cursorline / float background
  base02 = "#5350cc", -- visual selection
  base03 = "#8b87c2", -- comments, folds, line-fill
  base04 = "#9a97ff", -- line numbers, statusline fg
  base05 = "#aaa6f5", -- default foreground (matches wezterm text)
  base06 = "#cfccff", -- light foreground
  base07 = "#ffffff", -- white
  base08 = "#d98a8f", -- light red: variables, errors, diff delete
  base09 = "#edf171", -- yellow: numbers, constants, booleans
  base0A = "#edf171", -- yellow: types
  base0B = "#a9ff9f", -- light green: strings
  base0C = "#75cec8", -- cyan: support, escapes, regex
  base0D = "#9a97ff", -- light blue: functions
  base0E = "#c98fd0", -- light purple: keywords
  base0F = "#b2b2b2", -- light grey: deprecated, punctuation
}

return {
  { "RRethy/nvim-base16", lazy = false, priority = 1000 },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        if nvim_scheme then
          vim.cmd.colorscheme(nvim_scheme)
        else
          require("base16-colorscheme").setup(c64)
          vim.g.colors_name = "c64"
        end
      end,
    },
  },
}
