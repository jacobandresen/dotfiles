-- Run from the repository root:
-- NVIM_LOG_FILE=/tmp/nvim-tests.log nvim --headless -u NONE -i NONE -l nvim/tests/performance.lua
package.path = vim.fn.getcwd() .. "/nvim/lua/?.lua;" .. package.path
for _, file in ipairs(vim.fn.glob("nvim/**/*.lua", false, true)) do assert(loadfile(file)) end

local requests, timers, notices = {}, {}, {}
vim.notify = function(message) notices[#notices + 1] = message end
vim.system = function(cmd, _, cb)
  requests[#requests + 1] = { cmd = cmd, cb = cb }
  return { wait = function() error("Blocking process wait") end }
end
vim.uv.new_timer = function()
  local timer = {}
  function timer:start(_, interval, cb) self.interval, self.callback = interval, cb end
  function timer:stop() self.stopped = true end
  function timer:close() self.closed = true end
  timers[#timers + 1] = timer
  return timer
end
local now = 10000
vim.uv.now = function() return now end
local function flush()
  vim.wait(20, function() return false end, 1)
end
local function respond(stdout, code)
  local request = table.remove(requests, 1)
  assert(request, "No pending request")
  request.cb({ code = code or 0, stdout = stdout or "", stderr = code and "test failure" or "" })
  flush()
end

-- Reading the AI spec must not start polling or make a request.
package.loaded["util.copilot"] = { is_configured = function() return false end }
dofile("nvim/lua/plugins/ai.lua")
assert(#requests == 0 and #timers == 0)
local ollama = require("util.ollama")
package.loaded.minuet = { config = { provider_options = { openai_compatible = {} } } }
ollama.setup()
assert(#requests == 1 and #timers == 1)
respond(vim.json.encode({ models = { { name = "first" } } }))
now = now + 6000
timers[1].callback()
flush()
assert(#requests == 0, "Idle AI must not poll")
local original_mode = vim.fn.mode
vim.fn.mode = function() return "i" end
vim.b.minuet_virtual_text_auto_trigger = true
timers[1].callback()
flush()
assert(#requests == 1, "Active ghost text must refresh")
ollama.refresh()
assert(#requests == 1, "Ollama requests must not overlap")
respond(vim.json.encode({ models = { { name = "second" } } }))
assert(package.loaded.minuet.config.provider_options.openai_compatible.model == "second")
vim.fn.mode = original_mode

-- Cloud chat does not keep local-model polling active.
vim.bo.filetype = "codecompanion"
local adapter_name = "copilot"
package.loaded.codecompanion = { buf_get_chat = function() return { adapter = { name = adapter_name } } end }
now = now + 6000
timers[1].callback()
flush()
assert(#requests == 0)
adapter_name = "ollama"
timers[1].callback()
flush()
assert(#requests == 1)
respond(vim.json.encode({ models = { { name = "third" } } }))
vim.bo.filetype = ""

-- Async Docker loads share requests and notify all subscribers.
LazyVim = { root = function() return "/tmp/nvim-perf-empty-root-not-created" end }
local docker = require("util.compose.docker")
local completions = 0
local function completed(changed) assert(changed); completions = completions + 1 end
assert(not docker.ensure({ "ps" }, completed))
assert(not docker.ensure({ "ps" }, completed))
assert(#requests == 1)
respond("")
assert(completions == 2 and docker.ensure({ "ps" }))
docker.load({}, function(changed) assert(not changed); completions = completions + 1 end)
assert(completions == 3)
-- Failures release deduplication state so the next load can retry.
docker.load({ "networks" }, function(changed) assert(not changed) end)
respond("", 1)
assert(docker.raw.networks == nil)
docker.load({ "networks" }, function(changed) assert(changed) end)
assert(#requests == 1)
respond("")

local compose_checked = 0
for _ = 1, 2 do docker.check_compose(function(available) assert(available); compose_checked = compose_checked + 1 end) end
assert(#requests == 1)
respond("")
assert(compose_checked == 2 and docker.has_compose())

-- Finder returns a loading row, then redraws on async completion.
local refreshes = 0
package.loaded["util.compose.actions"] = { refresh = function() refreshes = refreshes + 1 end }
local compose = require("util.compose")
docker.invalidate()
local opts = { view = "containers", grouping = "project" }
local picker = { opts = opts, closed = false }
local items = compose.source.finder(opts, { picker = picker })
assert(items[1].kind == "loading" and #requests == 1)
respond("")
assert(refreshes == 1)
assert(#compose.source.finder(opts, { picker = picker }) == 0)
-- Disk usage is refreshed every 30 seconds, not every two seconds.
docker.raw.df = "cached"
picker.opts.view = "images"
compose.source.on_show(picker)
respond("") -- initial stats
local poller = timers[#timers]
for tick = 1, 15 do
  poller.callback()
  flush()
  local count = #requests
  assert(count == (tick == 15 and 2 or 1))
  for _ = 1, count do
    local kind = requests[1].cmd[2]
    respond(kind == "system" and "{}" or "")
  end
end
compose.source.on_close()
assert(poller.stopped)

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
vim.cmd = original_cmd
vim.api.nvim_exec_autocmds("VimLeavePre", {})
assert(timers[1].closed and timers[#timers].closed)
print("PASS: syntax, demand-driven AI, async Docker, request deduplication, polling frequency, visible log refresh and cleanup")
