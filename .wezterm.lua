local wezterm = require("wezterm")

local config = wezterm.config_builder()

config.initial_cols = 80
config.initial_rows = 40

config.color_scheme = "Apple Classic"
config.font = wezterm.font_with_fallback({ "Hack Nerd Font Mono", "Hack" })
config.font_size = 12

config.default_cursor_style = "BlinkingBlock"
config.cursor_blink_rate = 530
config.enable_scroll_bar = true
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false
config.window_decorations = "INTEGRATED_BUTTONS | RESIZE"
config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }

return config
