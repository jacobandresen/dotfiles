local wezterm = require("wezterm")

local config = wezterm.config_builder()

config.initial_cols = 120
config.initial_rows = 40

-- Turbo Pascal / Borland blue, matched to Midnight Commander's default skin
-- (_default_ = lightgray;blue, selected = black;cyan, marked = yellow;blue).
-- NOTE: no config.color_scheme here on purpose -- colorscheme.lua keys off its
-- absence to load Neovim's Borland classic theme, keeping the two in sync.
config.colors = {
  foreground = "#aaaaaa", -- lightgray
  background = "#0000aa", -- DOS blue
  cursor_bg = "#ffff55", -- yellow block cursor
  cursor_fg = "#0000aa",
  cursor_border = "#ffff55",
  selection_fg = "#000000", -- black on cyan (mc "selected")
  selection_bg = "#00aaaa",
  -- standard CGA/DOS 16-color palette
  ansi = {
    "#000000", -- black
    "#aa0000", -- red
    "#00aa00", -- green
    "#aa5500", -- brown
    "#0000aa", -- blue
    "#aa00aa", -- magenta
    "#00aaaa", -- cyan
    "#aaaaaa", -- lightgray
  },
  brights = {
    "#555555", -- gray
    "#ff5555", -- bright red
    "#55ff55", -- bright green
    "#ffff55", -- yellow
    "#5555ff", -- bright blue
    "#ff55ff", -- bright magenta
    "#55ffff", -- bright cyan
    "#ffffff", -- white
  },
  tab_bar = {
    background = "#0000aa",
    active_tab = { bg_color = "#00aaaa", fg_color = "#000000" },
    inactive_tab = { bg_color = "#0000aa", fg_color = "#aaaaaa" },
    inactive_tab_hover = { bg_color = "#00aaaa", fg_color = "#000000" },
    new_tab = { bg_color = "#0000aa", fg_color = "#aaaaaa" },
    new_tab_hover = { bg_color = "#00aaaa", fg_color = "#000000" },
  },
}

config.font_size = 14

config.default_cursor_style = "BlinkingBlock"
config.cursor_blink_rate = 530
config.enable_tab_bar = true
config.enable_scroll_bar = true

config.window_padding = { left = 4, right = 4, top = 4, bottom = 4 }

-- HiDPI fix: the native Wayland backend crashes / shows a black window under
-- fractional display scaling. Run via XWayland instead, which scales reliably.
config.enable_wayland = false

return config
