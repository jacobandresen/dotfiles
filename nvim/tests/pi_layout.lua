-- Run: timeout 30 nvim --headless -u NONE -i NONE -l nvim/tests/pi_layout.lua
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
local function command(...)
  local result = vim.system({ ... }, { cwd = temp, text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
command("git", "init", "-b", "main")
command("git", "config", "user.name", "Test")
command("git", "config", "user.email", "test@example.invalid")
vim.fn.writefile({ "before" }, temp .. "/file.txt")
command("git", "add", ".")
command("git", "commit", "-m", "Initial")
vim.fn.writefile({ "after" }, temp .. "/file.txt")
local uv = vim.uv
local input, output, errors = uv.new_pipe(false), uv.new_pipe(false), uv.new_pipe(false)
local unpacker = vim.mpack.Unpacker()
local replies, sequence, stderr = {}, 0, {}
local process = assert(uv.spawn("nvim", {
  args = { "--embed", "--headless", "-u", "NONE", "-i", "NONE" },
  stdio = { input, output, errors },
}, function() end))
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
errors:read_start(function(_, data)
  if data then stderr[#stderr + 1] = data end
end)
local function rpc(method, ...)
  sequence = sequence + 1
  input:write(vim.mpack.encode({ 0, sequence, method, { ... } }))
  assert(vim.wait(5000, function() return replies[sequence] ~= nil end, 10), method .. ": " .. table.concat(stderr))
  local reply = replies[sequence]
  if reply[3] ~= vim.NIL then error(vim.inspect(reply[3])) end
  return reply[4]
end
local function lua(code, args) return rpc("nvim_exec_lua", code, args or {}) end
local ok, failure = pcall(function()
  rpc("nvim_ui_attach", 140, 40, { rgb = true, ext_linegrid = true })
  lua(
    [[
    local root, snacks, temp = ...
    vim.opt.rtp:prepend(root .. "/nvim")
    vim.opt.rtp:append(snacks)
    _G.Snacks = require("snacks")
    Snacks.setup({ picker = { enabled = true }, notifier = { enabled = false } })
    local core = require("util.pi_issues")
    vim.g.pi_issues = { state_dir = temp .. "/state" }
    _G.LazyVim = { root = setmetatable({ detectors = {}, cache = {} }, { __call = function() return temp end }) }
    _G.workspace = {
      id = "test", path = temp, common = temp .. "/.git", branch = "main",
      repo = "test/repo", number = 42, title = "Readable issue review", base_ref = "main",
    }
    core.workspaces.test = workspace
    require("util.pi_issues_ui").setup()
    core.open(workspace)
  ]],
    { vim.fn.getcwd(), vim.fn.stdpath("data") .. "/lazy/snacks.nvim", temp }
  )
  for _, width in ipairs({ 140, 80 }) do
    rpc("nvim_ui_try_resize", width, 40)
    lua("require('util.pi_issues_ui').review(workspace)")
    assert(
      vim.wait(
        5000,
        function()
          return lua([[
        local picker = Snacks.picker.get()[1]
        if not picker or not picker.preview.win:valid() then return false end
        return table.concat(vim.api.nvim_buf_get_lines(picker.preview.win.buf, 0, -1, false), "\n"):find("+after", 1, true) ~= nil
      ]])
        end,
        20
      ),
      "Preview did not render at " .. width .. " columns"
    )
    lua([[
      local p = Snacks.picker.get()[1]
      local preview, files = p.preview.win.win, p.list.win.win
      assert(vim.api.nvim_win_get_position(preview)[2] + vim.api.nvim_win_get_width(preview)
        <= vim.api.nvim_win_get_position(files)[2], "Selector overlaps the diff")
      assert(vim.api.nvim_win_get_width(preview) > vim.api.nvim_win_get_width(files), "Preview must be wider")
      p:close()
    ]])
  end
  lua([[
    local ui = require("util.pi_issues_ui")
    ui.dashboard()
    local config = vim.api.nvim_win_get_config(0)
    assert(config.relative == "editor" and config.width <= vim.o.columns - 4)
    assert(vim.wo.cursorline and vim.wo.signcolumn == "no")
    vim.cmd.close()
  ]])
  rpc("nvim_ui_try_resize", 140, 40)
  lua("require('util.pi_issues_ui').dashboard()")
  rpc("nvim_ui_try_resize", 80, 24)
  lua([[
    local config = vim.api.nvim_win_get_config(0)
    assert(config.width + 2 <= vim.o.columns, "Workspace panel is wider than the resized editor")
    assert(config.col + config.width + 2 <= vim.o.columns, "Workspace panel is off-screen after resize")
    vim.cmd.close()
  ]])
  lua([[
    local core, ui = require("util.pi_issues"), require("util.pi_issues_ui")
    _G.original_repository, _G.original_run, _G.original_launch = core.repository, core.run, ui.launch
    core.repository = function()
      return { root = workspace.path, host = "github.com", repo = "test/repo", default_branch = "main" }
    end
    core.run = function(argv, ...)
      if argv[1] == "gh" then
        return { code = 0, stdout = vim.json.encode({
          { number = 1, title = "First issue" }, { number = 2, title = "Second issue" }, { number = 3, title = "Third issue" },
        }) }
      end
      return original_run(argv, ...)
    end
    ui.launch = function(repo, issues) _G.selected_issues = { repo = repo.repo, issues = issues } end
    ui.dashboard()
    _G.issue_dashboard_win = vim.api.nvim_get_current_win()
  ]])
  rpc("nvim_input", "i")
  assert(vim.wait(3000, function() return lua("return Snacks.picker.get()[1] ~= nil") end, 10))
  lua(
    "assert(not vim.api.nvim_win_is_valid(issue_dashboard_win), 'i must replace the workspace panel with the issue picker')"
  )
  rpc("nvim_input", "<Tab><Tab>")
  assert(
    vim.wait(3000, function() return lua("return #Snacks.picker.get()[1]:selected() == 2") end, 10),
    "Tab must select multiple GitHub issues"
  )
  rpc("nvim_input", "<CR>")
  assert(vim.wait(3000, function() return lua("return _G.selected_issues ~= nil") end, 10))
  lua([[
    assert(selected_issues.repo == "test/repo" and #selected_issues.issues == 2)
    assert(selected_issues.issues[1].number ~= selected_issues.issues[2].number)
    local core, ui = require("util.pi_issues"), require("util.pi_issues_ui")
    ui.issues()
  ]])
  assert(vim.wait(3000, function() return lua("return Snacks.picker.get()[1] ~= nil") end, 10))
  lua([[
    local core = require("util.pi_issues")
    core.repository = function() error("Server search must retain the selected repository") end
    core.input = function()
      _G.search_thread = coroutine.running()
      return coroutine.yield()
    end
    local picker = Snacks.picker.get()[1]
    picker.opts.actions.server_search(picker)
    assert(coroutine.resume(search_thread, "needle"))
  ]])
  assert(
    vim.wait(3000, function() return lua("return Snacks.picker.get()[1] ~= nil") end, 10),
    "Server search must keep its original repository across asynchronous input"
  )
  lua([[
    local core, ui = require("util.pi_issues"), require("util.pi_issues_ui")
    Snacks.picker.get()[1]:close()
    core.repository, core.run, ui.launch = original_repository, original_run, original_launch
    core.workspaces.second = vim.tbl_extend("force", workspace, { id = "second", number = 43, title = "Second issue" })
    ui.dashboard()
    vim.api.nvim_win_set_cursor(0, { 7, 0 })
    core.workspaces.earlier = vim.tbl_extend("force", workspace, { id = "earlier", number = 1, title = "Inserted issue" })
    core.changed()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    assert(vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]:find("#43", 1, true),
      "Live refresh must preserve the selected workspace, not its old row")
    vim.cmd.close()
  ]])
  lua([[
    local core, ui = require("util.pi_issues"), require("util.pi_issues_ui")
    core.repository = function()
      return { root = workspace.path, host = "github.com", repo = "test/empty", default_branch = "main" }
    end
    core.run = function(argv, ...)
      if argv[1] == "gh" then return { code = 0, stdout = "[]" } end
      return original_run(argv, ...)
    end
    ui.dashboard()
    _G.empty_dashboard_win = vim.api.nvim_get_current_win()
  ]])
  rpc("nvim_input", "i")
  assert(
    vim.wait(3000, function() return lua("return Snacks.picker.get()[1] ~= nil") end, 10),
    "An empty repository must leave a visible issue picker instead of silently closing"
  )
  lua([[
    local picker = Snacks.picker.get()[1]
    assert(picker:count() == 0 and picker.opts.title == "No open issues / test/empty")
    assert(not vim.api.nvim_win_is_valid(empty_dashboard_win))
    picker:close()
    local core = require("util.pi_issues")
    core.repository, core.run = original_repository, original_run
  ]])
end)
process:kill("sigterm")
for _, handle in ipairs({ input, output, errors, process }) do
  if not handle:is_closing() then handle:close() end
end
vim.fn.delete(temp, "rf")
if not ok then
  io.stderr:write(tostring(failure) .. "\n")
  vim.cmd("cquit 1")
end
print("pi UI: diff geometry, live resizing, multiselection, scoped search and dashboard refresh passed")
vim.cmd("qa!")
