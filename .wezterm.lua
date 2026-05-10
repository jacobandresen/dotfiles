local wezterm = require("wezterm")

local config = wezterm.config_builder()

config.initial_cols = 120
config.initial_rows = 40

config.color_scheme = "Atelier Forest Light (base16)"

config.font_size = 14

config.default_cursor_style = "BlinkingBlock"
config.cursor_blink_rate = 530

config.enable_tab_bar = true
config.enable_scroll_bar = true
-- config.window_decorations = "TITLE | RESIZE "

-- Tight padding to match CMD's edge-to-edge text
config.window_padding = { left = 4, right = 4, top = 4, bottom = 4 }

return config
