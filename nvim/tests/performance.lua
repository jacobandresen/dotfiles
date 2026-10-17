-- Run from the repository root:
-- NVIM_LOG_FILE=/tmp/nvim-tests.log nvim --headless -u NONE -i NONE -l nvim/tests/performance.lua
package.path = vim.fn.getcwd() .. "/nvim/lua/?.lua;" .. package.path
for _, file in ipairs(vim.fn.glob("nvim/**/*.lua", false, true)) do assert(loadfile(file)) end

dofile("nvim/lua/config/autocmds.lua")

local file = vim.fn.tempname() .. ".log"
vim.fn.writefile({ "before" }, file)
vim.cmd.edit(vim.fn.fnameescape(file))
assert(vim.bo.autoread, "Log buffers should allow automatic reload")

vim.fn.writefile({ "after" }, file)
local changed = os.time() + 2
vim.uv.fs_utime(file, changed, changed)
vim.api.nvim_exec_autocmds("FocusGained", {})
assert(vim.wait(100, function()
  return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "after"
end), "Focus should reload the log")

vim.fn.delete(file)
print("PASS: syntax and focus-based log reload")
