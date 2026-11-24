-- Shared harness for end-to-end pi task tests: an isolated copy of the real LazyVim config
-- in an embedded Neovim, driven through RPC with real keystrokes.
-- opts.stub: replace pi with the scripted offline agent (default true).
-- opts.env: extra environment for the editor and the pi processes it starts.
local uv = vim.uv
return function(opts)
opts = opts or {}
local repo_root = vim.fn.getcwd()
-- Not vim.fn.tempname(): Neovim removes that directory on exit, which defeats PI_E2E_KEEP.
local temp = assert(uv.fs_mkdtemp(uv.os_tmpdir() .. "/" .. (opts.name or "pi-e2e") .. "-XXXXXX"))
local repo = temp .. "/project"
local log_file, release = temp .. "/agents.jsonl", temp .. "/release"
local verbose = vim.env.PI_E2E_VERBOSE == "1"
local keep = vim.env.PI_E2E_KEEP == "1"
vim.fn.mkdir(repo, "p")
vim.fn.mkdir(temp .. "/bin", "p")
vim.fn.mkdir(temp .. "/data/nvim", "p")
assert(uv.fs_symlink(vim.fn.stdpath("data") .. "/lazy", temp .. "/data/nvim/lazy"))

local function sh(argv, cwd)
  local result = vim.system(argv, { cwd = cwd or repo, text = true }):wait()
  assert(result.code == 0, table.concat(argv, " ") .. ": " .. (result.stderr or ""))
  return vim.trim(result.stdout)
end
sh({ "git", "init", "-b", "main" })
sh({ "git", "config", "user.name", "Test" })
sh({ "git", "config", "user.email", "test@example.invalid" })
vim.fn.writefile({ "# Project", "", "Fixture for pi task tests." }, repo .. "/README.md")
vim.fn.writefile({ "def greet():", "    return 'hi'" }, repo .. "/app.py")
sh({ "git", "add", "." })
sh({ "git", "commit", "-m", "Initial" })

-- The editor keeps its default "pi" command; PATH resolves it to the scripted agent.
if opts.stub ~= false then vim.fn.writefile({ "#!/bin/sh", "exec python3 " .. vim.fn.shellescape(repo_root .. "/nvim/tests/fixtures/pi_agent.py") .. ' "$@"' },
  temp .. "/bin/pi")
assert(uv.fs_chmod(temp .. "/bin/pi", 493)) end
vim.fn.writefile({
  "vim.opt.rtp:prepend(" .. vim.inspect(repo_root .. "/nvim") .. ")",
  "require('config.lazy')",
  "local config, plugin = require('lazy.core.config'), require('lazy.core.plugin')",
  "for _, name in ipairs({ 'mason.nvim', 'mason-lspconfig.nvim', 'nvim-treesitter' }) do",
  "  if config.plugins[name] then plugin.values(config.plugins[name], 'opts', false).ensure_installed = {} end",
  "end",
}, temp .. "/init.lua")

local env = vim.fn.environ()
env.PATH = temp .. "/bin:" .. env.PATH
env.XDG_DATA_HOME, env.XDG_STATE_HOME, env.XDG_CACHE_HOME = temp .. "/data", temp .. "/state", temp .. "/cache"
env.NVIM_LOG_FILE, env.PI_E2E_LOG, env.PI_E2E_RELEASE = temp .. "/nvim.log", log_file, release
for key, value in pairs(opts.env or {}) do env[key] = value end
local env_list = {}
for key, value in pairs(env) do env_list[#env_list + 1] = key .. "=" .. value end

local input, output, errors, process
local replies, sequence, stderr, exited = {}, 0, {}, nil
local function close_editor()
  if process and exited == nil then
    -- :qa! runs VimLeavePre, which stops the editor's pi jobs; SIGKILL would orphan them.
    pcall(function() input:write(vim.mpack.encode({ 2, "nvim_command", { "qa!" } })) end)
    vim.wait(5000, function() return exited ~= nil end, 25)
    if exited == nil then process:kill("sigkill") end
    vim.wait(500)
  end
  for _, handle in ipairs({ input, output, errors, process }) do
    if handle and not handle:is_closing() then handle:close() end
  end
end
local function start_editor()
  close_editor()
  input, output, errors = uv.new_pipe(false), uv.new_pipe(false), uv.new_pipe(false)
  local unpacker = vim.mpack.Unpacker()
  replies, stderr, exited = {}, {}, nil
  process = assert(uv.spawn("nvim", {
    args = { "--embed", "-i", "NONE", "-u", temp .. "/init.lua", "README.md" },
    cwd = repo, env = env_list, stdio = { input, output, errors },
  }, function(code) exited = code end))
  output:read_start(function(err, data)
    assert(not err, err)
    if not data then return end
    local position = 1
    while position <= #data do
      local message
      message, position = unpacker(data, position)
      if message and message[1] == 1 then replies[message[2]] = message end
    end
  end)
  errors:read_start(function(_, data) if data then stderr[#stderr + 1] = data end end)
end

local function rpc(method, ...)
  sequence = sequence + 1
  local id = sequence
  input:write(vim.mpack.encode({ 0, id, method, { ... } }))
  assert(vim.wait(opts.rpc_timeout or 10000, function() return replies[id] ~= nil or exited ~= nil end, 5),
    method .. " timed out: " .. table.concat(stderr))
  assert(replies[id], "Editor exited during " .. method)
  local reply = replies[id]
  if reply[3] ~= vim.NIL then error(method .. ": " .. vim.inspect(reply[3]), 2) end
  return reply[4]
end
local function lua(code, ...) return rpc("nvim_exec_lua", code, { ... }) end
local function keys(text) rpc("nvim_input", text) end
local function messages()
  local ok, state = pcall(lua, [[
    local core = require("util.pi_issues")
    local lines = vim.deepcopy(_G.e2e_messages or {})
    if vim.notify ~= _G.e2e_notify then lines[#lines + 1] = "-- WARNING: vim.notify was replaced; capture incomplete" end
    lines[#lines + 1] = ("-- mode=%s ft=%s buftype=%s tabs=%d"):format(vim.fn.mode(), vim.bo.filetype, vim.bo.buftype,
      #vim.api.nvim_list_tabpages())
    for id, workspace in pairs(core.workspaces) do
      local job = core.jobs[id]
      lines[#lines + 1] = ("-- task %d %s activity=%s seq=%s model=%s"):format(workspace.number,
        core.status(workspace), job and job.activity or "-", job and tostring(job.sequence) or "-",
        job and tostring(job.model) or "-")
      if job and vim.api.nvim_buf_is_valid(job.buf) then
        local screen = vim.tbl_filter(function(line) return vim.trim(line) ~= "" end,
          vim.api.nvim_buf_get_lines(job.buf, 0, -1, false))
        for _, line in ipairs(vim.list_slice(screen, math.max(1, #screen - 11))) do
          lines[#lines + 1] = "   | " .. line
        end
      end
    end
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local config = vim.api.nvim_win_get_config(win)
      if config.relative ~= "" then lines[#lines + 1] = "-- float " .. vim.inspect(config.title) end
    end
    for _, line in ipairs(vim.split(vim.fn.execute("messages"), "\n")) do lines[#lines + 1] = ":messages " .. line end
    return lines
  ]])
  return ok and table.concat(state, "\n") or ("(editor state unavailable: " .. tostring(state) .. ")")
end
local function wait_for(label, code, timeout, ...)
  if vim.env.PI_E2E_TRACE == "1" then print("  wait: " .. label) end
  local args, deadline = { ... }, uv.now() + (timeout or 8000)
  -- Poll without nesting vim.wait: rpc() must be able to time out on its own.
  while lua(code, unpack(args)) ~= true do
    assert(uv.now() < deadline, label .. "\nMessages:\n" .. messages())
    vim.wait(25)
    uv.update_time()
  end
end
local function agents()
  local events = {}
  if not uv.fs_stat(log_file) then return events end
  for _, line in ipairs(vim.fn.readfile(log_file)) do events[#events + 1] = vim.json.decode(line) end
  return events
end
-- Choose from a vim.ui.select picker once the async matcher has settled on the intended item.
local function pick(filter, expected)
  keys(filter)
  wait_for("Picker must settle on " .. expected, [[
    local p = Snacks.picker.get()[1]
    local item = p and p:current()
    return item ~= nil and tostring(item.text):find(..., 1, true) ~= nil
  ]], 5000, expected)
  keys("<CR>")
end
local function step(name) if verbose then print("e2e: " .. name) end end

-- Child-side helpers for inspecting editor state.
local helpers = [[
  -- Record every notification, even after noice/snacks install their own vim.notify.
  _G.e2e_messages = {}
  local notify = rawget(vim, "notify")
  local function capture(message, ...)
    table.insert(_G.e2e_messages, tostring(message))
    return notify(message, ...)
  end
  rawset(vim, "notify", nil)
  local meta = getmetatable(vim)
  local index, newindex = meta.__index, meta.__newindex
  meta.__index = function(t, key)
    if key == "notify" then return capture end
    return type(index) == "function" and index(t, key) or index[key]
  end
  meta.__newindex = function(t, key, value)
    if key == "notify" then notify = value return end
    if newindex then return newindex(t, key, value) end
    rawset(t, key, value)
  end
  _G.e2e = {}
  local core = require("util.pi_issues")
  function e2e.by_number(number)
    for _, workspace in pairs(core.workspaces) do
      if workspace.number == number then return workspace end
    end
  end
  function e2e.job(number)
    local workspace = e2e.by_number(number)
    return workspace and core.jobs[workspace.id]
  end
  function e2e.live()
    local count = 0
    for _, job in pairs(core.jobs) do
      if not job.exited then count = count + 1 end
    end
    return count
  end
  function e2e.float_lines(title)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local config = vim.api.nvim_win_get_config(win)
      if config.relative ~= "" and vim.inspect(config.title):find(title, 1, true) then
        return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), win
      end
    end
  end
  function e2e.prompt_open()
    return vim.bo.filetype == "snacks_input" or vim.fn.mode() == "c"
  end
  function e2e.dashboard_row(number)
    local lines = e2e.float_lines("Task Workspaces") or {}
    for row, line in ipairs(lines) do
      if line:find("/" .. number .. "%-") then return row end
    end
  end
]]

local function boot()
  start_editor()
  rpc("nvim_ui_attach", 160, 45, { rgb = true, ext_linegrid = true })
  wait_for("Editor did not finish starting", [[
    return vim.v.vim_did_enter == 1 and package.loaded["util.pi_issues_ui"] ~= nil
      and vim.fn.exists(":PiTasks") == 2
      and (not require("lazy.core.config").plugins["noice.nvim"] or package.loaded["noice"] ~= nil)
  ]], 20000)
  vim.wait(300)
  lua(helpers)
  lua("_G.e2e_notify = vim.notify")
  lua([[assert(vim.g.mapleader == " ", "Tests assume the Space leader")]])
end

local H = {
  temp = temp, repo = repo, release = release, sh = sh, rpc = rpc, lua = lua, keys = keys, wait_for = wait_for,
  pick = pick, step = step, agents = agents, messages = messages, boot = boot, close = close_editor,
}
function H.exited() return exited end
-- Run the scenario, clean up, report and exit the host editor.
function H.run(summary, scenario)
  local ok, failure = pcall(scenario)
  close_editor()
  if not ok then
    io.stderr:write(keep and ("kept test files in " .. temp .. "\n")
      or "rerun with PI_E2E_KEEP=1 to keep the test repository, state and logs\n")
  end
  if ok or not keep then
    vim.fn.delete(temp, "rf")
    for _, path in ipairs(opts.cleanup or {}) do vim.fn.delete(path, "rf") end
  end
  if not ok then
    io.stderr:write(tostring(failure) .. "\n")
    vim.cmd("cquit 1")
  end
  print(summary)
  vim.cmd("qa!")
end
return H
end
