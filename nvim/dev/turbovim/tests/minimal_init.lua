local script     = debug.getinfo(1, "S").source:sub(2)
local tests_dir  = vim.fn.fnamemodify(script, ":p:h")
local plugin_dir = vim.fn.fnamemodify(tests_dir, ":h")

vim.opt.runtimepath:prepend(plugin_dir)
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/lazy/plenary.nvim")

require("turbovim").setup({})
