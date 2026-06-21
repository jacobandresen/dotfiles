local opt = vim.opt

opt.relativenumber = false
opt.number = true

opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.autoindent = true

opt.wrap = false

opt.ignorecase = true
opt.smartcase = true

opt.cursorline = false

opt.termguicolors = true
opt.background = "dark"
opt.signcolumn = "yes"

opt.backspace = "indent,eol,start"
opt.clipboard:append("unnamedplus")

opt.splitright = true
opt.splitbelow = true

-- ufo folding
opt.foldcolumn = "0"
opt.foldlevel = 99
opt.foldlevelstart = 99
opt.foldenable = true

opt.iskeyword:append("-")

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.diagnostic.config({ virtual_text = false })

-- Python host for remote plugins (molten-nvim). Use the dedicated venv built by
-- `make setup-jupyter` if present; otherwise let nvim auto-detect so a missing
-- venv doesn't error on every startup.
local nvim_python = vim.fn.expand("~/.virtualenvs/neovim/bin/python3")
if vim.fn.executable(nvim_python) == 1 then
  vim.g.python3_host_prog = nvim_python
end

if vim.fn.has("gui_running") == 1 or vim.g.neovide then
  vim.o.guifont = "Terminess Nerd Font:h14"
end
