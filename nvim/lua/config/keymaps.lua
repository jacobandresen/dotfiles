local map = vim.keymap.set

-- clear search highlights
map("n", "<leader>nh", ":nohl<CR>", { desc = "Clear search highlights" })

-- delete single character without copying into register
map("n", "x", '"_x')

-- increment/decrement numbers
map("n", "<leader>=", "<C-a>", { desc = "Increment number" })
map("n", "<leader>-", "<C-x>", { desc = "Decrement number" })

-- window management
map("n", "<leader>sv", "<C-w>v", { desc = "Split vertical" })
map("n", "<leader>ss", "<C-w>s", { desc = "Split horizontal" })
map("n", "<leader>se", "<C-w>=", { desc = "Equal split sizes" })
map("n", "<leader>sx", ":close<CR>", { desc = "Close split" })
map("n", "<leader>sh", "<C-w>h", { desc = "Focus left split" })
map("n", "<leader>sl", "<C-w>l", { desc = "Focus right split" })
map("n", "<leader>sj", "<C-w>j", { desc = "Focus down split" })
map("n", "<leader>sk", "<C-w>k", { desc = "Focus up split" })
map("n", "<leader>s>", "<C-w>>", { desc = "Widen split" })
map("n", "<leader>s<", "<C-w><", { desc = "Narrow split" })

-- tab management
map("n", "<leader>tn", ":tabnew<CR>", { desc = "New tab" })
map("n", "<leader>tx", ":tabclose<CR>", { desc = "Close tab" })
map("n", "<leader>tk", ":tabn<CR>", { desc = "Next tab" })
map("n", "<leader>tj", ":tabp<CR>", { desc = "Prev tab" })

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

-- telescope
map("n", "<leader>ff", "<cmd>Telescope find_files no_ignore=true<cr>", { desc = "Find files" })
map("n", "<leader>fs", "<cmd>Telescope live_grep<cr>", { desc = "Live grep" })
map("n", "<leader>fc", "<cmd>Telescope grep_string<cr>", { desc = "Grep string under cursor" })
map("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { desc = "Buffers" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<cr>", { desc = "Help tags" })
map("n", "<leader>fcb", "<cmd>Telescope current_buffer_fuzzy_find fuzzy=false case_mode=ignore_case<cr>", { desc = "Buffer fuzzy find" })
map("n", "<leader>fj", "<cmd>Telescope jumplist<cr>", { desc = "Jumplist" })
map("n", "<leader>ft", "<cmd>Telescope colorscheme<cr>", { desc = "Colorschemes" })
map("n", "<leader>fgc", "<cmd>Telescope git_commits<cr>", { desc = "Git commits" })
map("n", "<leader>fgb", "<cmd>Telescope git_branches<cr>", { desc = "Git branches" })
map("n", "<leader>fgs", "<cmd>Telescope git_status<cr>", { desc = "Git status" })

-- misc
map("n", "<leader>rs", ":LspRestart<CR>", { desc = "Restart LSP" })
