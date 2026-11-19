-- Only deviations from LazyVim's defaults (lazyvim/config/options.lua).
local opt = vim.opt

vim.g.snacks_animate = false -- no animations anywhere
vim.g.trouble_lualine = false -- no symbol breadcrumb in the statusline
-- no remote-plugin hosts: nothing here needs them
for _, p in ipairs({ "python3", "node", "perl", "ruby" }) do vim.g["loaded_" .. p .. "_provider"] = 0 end

opt.background = "dark"
opt.relativenumber = false
opt.cursorline = false
opt.signcolumn = "auto:1" -- show diagnostic and breakpoint signs when present
opt.list = false -- no visible whitespace markers in the editor
opt.clipboard = "unnamedplus" -- LazyVim disables it over SSH; keep it on
opt.iskeyword:append("-")
opt.winborder = "rounded"
opt.pumblend = 0 -- opaque popups; blending shows code through blank cells
opt.showcmd = false
opt.statuscolumn = "" -- native gutter: numbers, signs only when present
opt.numberwidth = 3

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
