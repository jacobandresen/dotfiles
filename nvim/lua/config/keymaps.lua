local map = vim.keymap.set

-- delete single character without copying into register
map("n", "x", '"_x')

-- move lines in visual mode
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move line down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move line up" })

-- repeat paste in visual mode
map("x", "p", "P")

-- center screen on jumps / searches
map("n", "gd", "gdzz")
map("n", "<C-o>", "<C-o>zz")
map("n", "n", "nzz")
map("n", "N", "Nzz")
map("n", "Y", "^y$")
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")

-- file explorer (oil)
map("n", "<leader>e", "<CMD>Oil<CR>", { desc = "Open Oil" })

-- telescope: find
map("n", "<leader>ff", "<cmd>Telescope find_files no_ignore=true<cr>", { desc = "Find files" })
map("n", "<leader>fs", "<cmd>Telescope live_grep<cr>", { desc = "Live grep" })
map("n", "<leader>fc", "<cmd>Telescope grep_string<cr>", { desc = "Grep string under cursor" })
map("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { desc = "Buffers" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<cr>", { desc = "Help tags" })
map("n", "<leader>fcb", "<cmd>Telescope current_buffer_fuzzy_find fuzzy=false case_mode=ignore_case<cr>", { desc = "Buffer fuzzy find" })
map("n", "<leader>fj", "<cmd>Telescope jumplist<cr>", { desc = "Jumplist" })
map("n", "<leader>ft", "<cmd>Telescope colorscheme<cr>", { desc = "Colorschemes" })

-- telescope: git (aligned with LazyVim's <leader>g git prefix)
map("n", "<leader>gc", "<cmd>Telescope git_commits<cr>", { desc = "Git commits" })
map("n", "<leader>gB", "<cmd>Telescope git_branches<cr>", { desc = "Git branches" })
map("n", "<leader>gs", "<cmd>Telescope git_status<cr>", { desc = "Git status" })

-- misc
map("n", "<leader>rs", ":LspRestart<CR>", { desc = "Restart LSP" })
