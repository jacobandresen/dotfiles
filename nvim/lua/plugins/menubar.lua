-- Turbo Pascal / Borland-style menu bar.
--
-- The menu bar lives in the tabline, so bufferline is disabled here (one line to
-- revert). Open buffers are reachable from the Window and Tools menus, which is
-- how the original Turbo Pascal IDE listed windows anyway.
--
-- Activation:
--   * mouse-click a menu name in the bar
--   * :TPMenu [name]   (e.g. :TPMenu File)
--   * <M-f> / <M-e> / ...  -- requires the terminal to forward Alt as Meta.
--     In WezTerm that means setting, in ~/.wezterm.lua:
--         config.send_composed_key_when_left_alt_is_pressed = false
--     Without it, use the mouse or :TPMenu instead.

vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("TurboPascalMenu", { clear = true }),
  pattern = "VeryLazy",
  callback = function() require("menubar").setup() end,
})

return {
  { "akinsho/bufferline.nvim", enabled = false },
}
