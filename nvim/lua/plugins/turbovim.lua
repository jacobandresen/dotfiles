return {
  -- Disable LazyVim's bufferline — turbovim owns the tabline.
  { "akinsho/bufferline.nvim", enabled = false },

  {
    dir      = vim.fn.stdpath("config") .. "/dev/turbovim",
    name     = "turbovim",
    lazy     = false,
    priority = 1000,
    config   = function()
      require("turbovim").setup({
        key = "<F10>",
      })
    end,
  },
}
