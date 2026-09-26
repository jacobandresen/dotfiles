-- Only additions/deviations; LazyVim already provides window resize
-- (<C-arrows>), line moving (<A-j>/<A-k>), and tabs (<leader><tab>...).
local map = vim.keymap.set

-- delete single character without copying into register
map("n", "x", '"_x')

-- paste over a selection without losing the register, so it can be repeated
map("x", "p", "P")

-- yank to end of line, starting at the first non-blank
map("n", "Y", "^y$")

-- center screen on jumps/searches (zv opens folds). n/N keep LazyVim's
-- "n always searches forward" behaviour.
map("n", "n", "'Nn'[v:searchforward].'zzzv'", { expr = true, desc = "Next Search Result" })
map("n", "N", "'nN'[v:searchforward].'zzzv'", { expr = true, desc = "Prev Search Result" })
map("n", "<C-o>", "<C-o>zzzv")
map("n", "<C-d>", "<C-d>zzzv")
map("n", "<C-u>", "<C-u>zzzv")

-- telescope: only deviations from LazyVim's own <leader>f/s defaults
map("n", "<leader>ff", "<cmd>Telescope find_files no_ignore=true<cr>", { desc = "Find Files (incl. ignored)" })
map("n", "<leader>sB", "<cmd>Telescope current_buffer_fuzzy_find fuzzy=false case_mode=ignore_case<cr>", { desc = "Buffer Lines (exact)" })

-- lazydocker, same pattern as LazyVim's own <leader>gg (Lazygit)
map("n", "<leader>gd", function() require("turbo.menus").lazydocker() end, { desc = "Lazydocker" })

-- LSP restart next to LazyVim's <leader>cl (Lsp Info)
map("n", "<leader>cL", "<cmd>lsp restart<cr>", { desc = "Restart LSP" })

-- text transforms (JSON/URL/HTML/Base64) on the selection or whole buffer
local transform = require("util.transform")
map("n", "<leader>ct", transform.pick, { desc = "Transform Buffer" })
map("x", "<leader>ct", transform.pick, { desc = "Transform Selection" })

-- Turbo Pascal 7.0 keys: F10/Alt+letter menus, F2 save, F3 open, F9 make...
require("turbo").keymaps()
