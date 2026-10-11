-- Run from the repository root:
-- NVIM_LOG_FILE=/tmp/nvim-tests.log nvim --headless -u NONE -i NONE -l nvim/tests/performance.lua
package.path = vim.fn.getcwd() .. "/nvim/lua/?.lua;" .. package.path
for _, file in ipairs(vim.fn.glob("nvim/**/*.lua", false, true)) do assert(loadfile(file)) end

local timers = {}
vim.uv.new_timer = function()
  local timer = {}
  function timer:start(_, interval, cb) self.interval, self.callback = interval, cb end
  function timer:stop() self.stopped = true end
  function timer:close() self.closed = true end
  timers[#timers + 1] = timer
  return timer
end
local function flush()
  vim.wait(20, function() return false end, 1)
end

-- A single log timer checks only displayed log buffers.
local checks = {}
local original_cmd = vim.cmd
vim.cmd = setmetatable({}, { __call = function(_, command)
  local buf = command:match("^checktime (%d+)$")
  if buf then checks[tonumber(buf)] = true else original_cmd(command) end
end })
dofile("nvim/lua/config/autocmds.lua")
local visible = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(visible, "/tmp/visible-performance.log")
vim.api.nvim_exec_autocmds("BufRead", { buffer = visible })
local timer_count = #timers
local hidden = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(hidden, "/tmp/hidden-performance.jsonl")
vim.api.nvim_exec_autocmds("BufRead", { buffer = hidden })
assert(#timers == timer_count)
timers[#timers].callback()
flush()
assert(checks[visible] and not checks[hidden])
vim.api.nvim_set_current_buf(hidden)
flush()
assert(checks[hidden], "Hidden logs must refresh when displayed")
local active_log_timer = timers[#timers]
local scratch = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(scratch)
flush()
assert(active_log_timer.stopped and active_log_timer.closed, "Closing the last visible log must stop its timer")
vim.api.nvim_set_current_buf(hidden)
flush()
assert(timers[#timers] ~= active_log_timer and not timers[#timers].closed, "Reopening a log must restart polling")
vim.cmd = original_cmd
vim.api.nvim_exec_autocmds("VimLeavePre", {})
assert(timers[#timers].closed)
print("PASS: syntax, visible log refresh and cleanup")
