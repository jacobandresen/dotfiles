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

-- telescope: only deviations from LazyVim's own <leader>f/s/g defaults;
-- everything else (grep, buffers, help, jumplist, git, etc.) is already covered.
map("n", "<leader>ff", "<cmd>Telescope find_files no_ignore=true<cr>", { desc = "Find files (incl. ignored)" })
map("n", "<leader>sB", "<cmd>Telescope current_buffer_fuzzy_find fuzzy=false case_mode=ignore_case<cr>", { desc = "Buffer lines (exact match)" })

-- lazydocker, same pattern as LazyVim's own <leader>gg (Lazygit)
map("n", "<leader>gd", function() require("snacks").terminal.open("lazydocker") end, { desc = "Lazydocker" })

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
