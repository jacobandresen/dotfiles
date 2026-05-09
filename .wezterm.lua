local wezterm = require("wezterm")

local config = wezterm.config_builder()

-- Classic 80x25 CMD window
config.initial_cols = 80
config.initial_rows = 25

config.color_scheme = "darkmoss (base16)"

config.font = wezterm.font_with_fallback({
	"Andale Mono",
	"Courier New",
})
config.font_size = 14

-- Blinking block cursor like CMD.EXE
config.default_cursor_style = "BlinkingBlock"
config.cursor_blink_rate = 530

-- Minimal chrome — just title bar and resize border
config.enable_tab_bar = false
config.enable_scroll_bar = false
config.window_decorations = "TITLE | RESIZE"

-- Tight padding to match CMD's edge-to-edge text
config.window_padding = { left = 4, right = 4, top = 4, bottom = 4 }

return config
