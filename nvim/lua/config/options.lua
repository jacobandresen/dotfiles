-- Only deviations from LazyVim's defaults (lazyvim/config/options.lua).
local opt = vim.opt

opt.background = "dark"
opt.relativenumber = false
opt.number = true
opt.cursorline = false
opt.signcolumn = "auto:1" -- show diagnostic and breakpoint signs when present
opt.list = false -- no visible whitespace markers in the editor
opt.clipboard = "unnamedplus" -- LazyVim disables it over SSH; keep it on
opt.foldlevelstart = 99 -- nvim-ufo (editor.lua)
opt.iskeyword:append("-")
opt.winborder = "rounded"
opt.pumblend = 0 -- opaque popups; blending shows code through blank cells

if vim.g.neovide then
  vim.o.guifont = "JetBrainsMono Nerd Font:h14"
end

-- Filetypes are registered here rather than in autocmds.lua, which LazyVim
-- loads lazily - too late for a file already open at startup.
vim.filetype.add({
  extension = { jsonl = "json" },
  filename = {
    ["docker-compose.yml"] = "yaml.docker-compose",
    ["docker-compose.yaml"] = "yaml.docker-compose",
    ["compose.yml"] = "yaml.docker-compose",
    ["compose.yaml"] = "yaml.docker-compose",
  },
  pattern = {
    [".*/docker%-compose%.[%w.-]+%.ya?ml"] = "yaml.docker-compose",
    [".*/compose%.[%w.-]+%.ya?ml"] = "yaml.docker-compose",
  },
})
