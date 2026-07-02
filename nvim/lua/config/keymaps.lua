local map = vim.keymap.set

-- delete single character without copying into register
map("n", "x", '"_x')

-- move lines in visual mode (using Alt+J/K to avoid conflict with join)
map("v", "<M-j>", ":m '>+1<CR>gv=gv", { desc = "Move line down" })
map("v", "<M-k>", ":m '<-2<CR>gv=gv", { desc = "Move line up" })

-- repeat paste in visual mode
map("x", "p", "P")

-- center screen on jumps / searches (zzzv opens folds too)
map("n", "gd", "gdzzzv")
map("n", "<C-o>", "<C-o>zzzv")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")
map("n", "Y", "^y$")
map("n", "<C-d>", "<C-d>zzzv")
map("n", "<C-u>", "<C-u>zzzv")

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

-- window navigation
map("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to window below" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to window above" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- window resizing
map("n", "<C-Up>",    "<cmd>resize +2<CR>", { desc = "Increase window height" })
map("n", "<C-Down>",  "<cmd>resize -2<CR>", { desc = "Decrease window height" })
map("n", "<C-Left>",  "<cmd>vertical resize -2<CR>", { desc = "Decrease window width" })
map("n", "<C-Right>", "<cmd>vertical resize +2<CR>", { desc = "Increase window width" })

-- tab navigation
map("n", "<leader>tn", "<cmd>tabnew<CR>", { desc = "New tab" })
map("n", "<leader>tk", "<cmd>tabnext<CR>", { desc = "Next tab" })
map("n", "<leader>tj", "<cmd>tabprevious<CR>", { desc = "Previous tab" })
map("n", "<leader>tc", "<cmd>tabclose<CR>", { desc = "Close tab" })

-- misc
map("n", "<leader>rs", ":LspRestart<CR>", { desc = "Restart LSP" })
