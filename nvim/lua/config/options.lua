-- Only deviations from LazyVim's defaults (lazyvim/config/options.lua).
local opt = vim.opt

opt.relativenumber = false
opt.number = false -- TP keeps the line and column in the hint line
opt.cursorline = false
opt.signcolumn = "auto:1" -- show diagnostic and breakpoint signs when present
opt.list = false -- no visible whitespace markers in the editor
opt.clipboard = "unnamedplus" -- LazyVim disables it over SSH; keep it on
opt.foldlevelstart = 99 -- nvim-ufo (editor.lua)
opt.iskeyword:append("-")
opt.winborder = "double" -- Turbo Vision window frames
opt.pumblend = 0 -- opaque popups; blending shows code through blank cells

-- Turbo Pascal menu bar, hint line and window frames (lua/turbo/)
require("turbo").setup()

if vim.g.neovide then
  vim.o.guifont = "BigBlueTermPlus Nerd Font Mono:h14"
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
