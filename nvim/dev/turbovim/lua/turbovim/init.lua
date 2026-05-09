local M = {}

M.defaults = {
  key = "<F10>",
}

function M.setup(opts)
  local config = vim.tbl_deep_extend("force", M.defaults, opts or {})
  local state  = require("turbovim.state")

  state.config = config
  state.menus  = require("turbovim.menus").get()

  require("turbovim.highlights").setup()
  require("turbovim.bar").setup()
  require("turbovim.keymaps").setup(config)

  local au = vim.api.nvim_create_augroup("TurboVim", { clear = true })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group    = au,
    callback = function() require("turbovim.highlights").setup() end,
  })


end

return M
