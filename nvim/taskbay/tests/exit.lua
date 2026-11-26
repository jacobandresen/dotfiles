-- Invoked by pi_extension.py in an isolated child editor.
local plugin = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(plugin)
vim.g.mapleader = " "
local core = require("taskbay.core")
vim.g.taskbay = { state_dir = vim.env.TASKBAY_EXIT_TEST_DIR .. "/state" }
core.setup()
local workspace = { id = "exit-test", path = vim.env.TASKBAY_EXIT_TEST_DIR }
core.workspaces[workspace.id] = workspace
local terminal = vim.api.nvim_create_buf(false, true)
vim.bo[terminal].bufhidden = "hide"
vim.api.nvim_set_current_buf(terminal)
local job = vim.fn.jobstart({ "sleep", "20" }, { term = true })
core.jobs[workspace.id] = { channel = job, activity = "working" }
core.choose = function() return vim.env.TASKBAY_EXIT_CHOICE == "1" and "Cancel" or "Stop agents and quit" end
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
if vim.env.TASKBAY_EXIT_DIRTY ~= "no" then vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved" }) end
if vim.env.TASKBAY_EXIT_DIRTY == "task" then vim.bo[buf].buftype = "acwrite" end
if vim.env.TASKBAY_EXIT_DIRTY ~= "no" then
  local ok = pcall(vim.cmd, "qall")
  assert(not ok, "Modified buffers must cancel the quit")
  assert(vim.fn.jobwait({ job }, 0)[1] == -1, "Cancelled exit must preserve the agent")
end
core.quit()
assert(vim.fn.jobwait({ job }, 0)[1] == -1, "Cancelled bulk quit must preserve the agent")
vim.fn.writefile({ "preserved" }, vim.env.TASKBAY_EXIT_TEST_DIR .. "/result")
core.jobs[workspace.id].exited = true
vim.fn.jobstop(job)
vim.fn.jobwait({ job }, 3000)
vim.cmd("qa!")
