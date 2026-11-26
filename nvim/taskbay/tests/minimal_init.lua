-- A minimal editor for the end-to-end tests: snacks.nvim and taskbay, nothing else.
-- TASKBAY_SNACKS points at a snacks.nvim checkout (default: lazy.nvim's, in the data directory).
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.g.mapleader = " "
vim.opt.rtp:prepend(vim.env.TASKBAY_SNACKS or (vim.fn.stdpath("data") .. "/lazy/snacks.nvim"))
vim.opt.rtp:prepend(root)
-- The notifier keeps multi-line notifications from stopping at a hit-enter prompt.
require("snacks").setup({ picker = { enabled = true }, input = { enabled = true }, notifier = { enabled = true } })
require("taskbay").setup({})
