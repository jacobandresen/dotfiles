local wezterm = require("wezterm")

local config = wezterm.config_builder()

config.initial_cols = 80
config.initial_rows = 40

-- Commodore 64 boot screen: light-blue text on blue with a light-blue blinking
-- block cursor -- the classic "READY." look. Based on the colodore VIC-II
-- palette, brightened a touch so text and highlights stay legible (the authentic
-- C64 blue-on-blue is too low-contrast to read for long).
-- NOTE: no config.color_scheme here on purpose -- colorscheme.lua keys off its
-- absence to load Neovim's matching C64 theme.
config.colors = {
	foreground = "#aaa6f5", -- brightened C64 light blue -- legible on the blue screen
	background = "#2e2c9b", -- C64 blue (screen)
	cursor_bg = "#aaa6f5", -- bright light-blue blinking block cursor
	cursor_fg = "#2e2c9b",
	cursor_border = "#aaa6f5",
	selection_fg = "#2e2c9b", -- reverse video (high contrast)
	selection_bg = "#aaa6f5",
	-- VIC-II 16-color palette (colodore)
	ansi = {
		"#000000", -- black
		"#813338", -- red
		"#56ac4d", -- green
		"#edf171", -- yellow
		"#5d5af5", -- blue (lightened so blue text isn't lost against the screen bg)
		"#8e3c97", -- purple
		"#75cec8", -- cyan
		"#b2b2b2", -- light grey
	},
	brights = {
		"#8b87c2", -- dark grey (lifted so dim/secondary text stays legible on blue)
		"#c46c71", -- light red
		"#a9ff9f", -- light green
		"#edf171", -- yellow (no brighter yellow on the C64)
		"#9a97ff", -- light blue
		"#8e3c97", -- purple
		"#75cec8", -- cyan
		"#ffffff", -- white
	},
	tab_bar = {
		background = "#2e2c9b",
		active_tab = { bg_color = "#706deb", fg_color = "#2e2c9b" },
		inactive_tab = { bg_color = "#2e2c9b", fg_color = "#706deb" },
		inactive_tab_hover = { bg_color = "#7b7b7b", fg_color = "#ffffff" },
		new_tab = { bg_color = "#2e2c9b", fg_color = "#706deb" },
		new_tab_hover = { bg_color = "#7b7b7b", fg_color = "#ffffff" },
	},
}

-- C64 Pro Mono: authentic PETSCII glyphs for the real Commodore look. Hack Nerd
-- Font Mono falls back behind it for any glyph C64 Pro lacks -- chiefly the icon
-- glyphs Neovim uses (oil/mini.icons, fidget, render-markdown) -- and the Mono
-- variant keeps those single-cell so the dashboard logo and Turbo Pascal menubar
-- stay aligned. Install both with `make install-fonts`; falls back to plain Hack
-- until then.
config.font = wezterm.font_with_fallback({ "C64 Pro Mono", "Hack Nerd Font Mono", "Hack" })
config.font_size = 12

config.default_cursor_style = "BlinkingBlock"
config.cursor_blink_rate = 530

-- DOS text mode filled the whole screen: no scrollbar, no tab strip in normal
-- use, no inner padding, and no title bar (just a resize border).
config.enable_scroll_bar = false
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"
config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }

return config
