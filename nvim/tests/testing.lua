-- Run: timeout 160 nvim --headless -u NONE -i NONE -l nvim/tests/testing.lua
-- Add NVIM_TEST_KAS=/home/jacob/Projects/KAS to exercise existing KAS unit tests.
local uv = vim.uv
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
end
local function git(...)
  local result = vim.system(vim.list_extend({ "git", "-C", temp }, { ... }), { text = true }):wait()
  assert(result.code == 0, result.stderr)
end
git("init", "-b", "main")
write(temp .. "/pytest.ini", { "[pytest]" })
write(temp .. "/test_live.py", {
  "import time",
  "import pytest",
  "import unittest",
  "from pathlib import Path",
  "",
  "def test_pass():",
  "    print('live test output', flush=True)",
  "    deadline = time.monotonic() + 20",
  "    while not Path(__file__).with_name('release-live-test').exists():",
  "        assert time.monotonic() < deadline, 'Live-output check did not release the test'",
  "        time.sleep(0.05)",
  "    assert 2 + 2 == 4",
  "",
  "def test_failure():",
  "    assert 2 + 2 == 5, 'expected fixture failure'",
  "",
  "@pytest.mark.skip(reason='fixture skip')",
  "def test_skipped():",
  "    assert False",
  "",
  "class TestStandardLibrary(unittest.TestCase):",
  "    def test_unittest_case(self):",
  "        self.assertEqual(3 + 3, 6)",
})
write(temp .. "/test_stop.py", { "import time", "def test_slow():", "    time.sleep(30)" })
write(temp .. "/node/package.json", { '{"devDependencies":{"vitest":"*"}}' })
write(temp .. "/node/vitest.config.ts", { "export default {}" })
write(temp .. "/node/packages/library/package.json", { '{"name":"library"}' })
write(temp .. "/node/packages/library/example.test.ts", { "test('example', () => {})" })
write(temp .. "/node/packages/library/e2e/example.spec.ts", { "test('not a unit test', () => {})" })
write(temp .. "/first/first.csproj", { "<Project />" })
write(temp .. "/second/second.csproj", { "<Project />" })
write(temp .. "/rust/deep/library/Cargo.toml", {
  "[package]",
  'name = "nvim_test_fixture"',
  'version = "0.1.0"',
  'edition = "2021"',
})
write(temp .. "/rust/deep/library/src/lib.rs", {
  "#[cfg(test)]",
  "mod tests {",
  "    #[test]",
  "    fn adds_numbers() { assert_eq!(2 + 2, 4); }",
  "    #[test]",
  '    fn compares_strings() { assert_eq!("test", "test"); }',
  "}",
  "#[cfg(test)]",
  "mod other_tests {",
  "    #[test]",
  '    fn reports_failure() { assert!(false, "expected Rust fixture failure"); }',
  "}",
})
write(temp .. "/rust/other/library/Cargo.toml", {
  "[package]",
  'name = "nvim_second_fixture"',
  'version = "0.1.0"',
  'edition = "2021"',
})
write(temp .. "/rust/other/library/src/lib.rs", {
  "#[cfg(test)]",
  "mod tests { #[test] fn second_project() { assert_eq!(3 + 3, 6); } }",
})
write(temp .. "/rust/test_workspace.py", {
  "import time",
  "from pathlib import Path",
  "def test_workspace():",
  "    hold = Path(__file__).with_name('hold-workspace-tests')",
  "    if hold.exists():",
  "        print('workspace test waiting', flush=True)",
  "    deadline = time.monotonic() + 20",
  "    while hold.exists():",
  "        assert time.monotonic() < deadline, 'Workspace test was not cancelled'",
  "        time.sleep(0.05)",
  "    assert 3 + 3 == 6",
})

local env = vim.fn.environ()
env.XDG_STATE_HOME = temp .. "/state"
env.XDG_CACHE_HOME = temp .. "/cache"
env.NVIM_LOG_FILE = temp .. "/nvim.log"
for name in pairs(env) do
  if name:match("^DB_UI_") or name == "DATABASE_URL" or name == "DBUI_URL" or name == "DBUI_NAME" then
    env[name] = nil
  end
end
env = vim.iter(env):map(function(key, value) return key .. "=" .. value end):totable()
local input, output, errors = uv.new_pipe(false), uv.new_pipe(false), uv.new_pipe(false)
local unpacker, replies, sequence, stderr, redraw = vim.mpack.Unpacker(), {}, 0, {}, {}
local exited
local process = assert(uv.spawn("nvim", {
  args = { "--embed", "--headless", "-u", "NONE", "-i", "NONE" },
  cwd = temp,
  env = env,
  stdio = { input, output, errors },
}, function(code, signal) exited = { code = code, signal = signal } end))
output:read_start(function(err, data)
  assert(not err, err)
  if not data then return end
  local position = 1
  while position <= #data do
    local message
    message, position = unpacker(data, position)
    if message and message[1] == 1 then replies[message[2]] = message end
    if message and message[1] == 2 and message[2] == "redraw" then
      for _, event in ipairs(message[3]) do
        if event[1] == "grid_line" then
          for index = 2, #event do
            local text = {}
            for _, cell in ipairs(event[index][4]) do
              text[#text + 1] = cell[1]
            end
            redraw[#redraw + 1] = table.concat(text)
            if #redraw > 200 then table.remove(redraw, 1) end
          end
        end
      end
    end
  end
end)
errors:read_start(function(_, data)
  if data then stderr[#stderr + 1] = data end
end)
local function rpc(method, ...)
  sequence = sequence + 1
  local id = sequence
  input:write(vim.mpack.encode({ 0, id, method, { ... } }))
  if not vim.wait(15000, function() return replies[id] ~= nil end, 10) then
    sequence = sequence + 1
    input:write(vim.mpack.encode({ 0, sequence, "nvim_get_mode", {} }))
    vim.wait(1000, function() return replies[sequence] ~= nil end, 10)
    error(
      method
        .. ": "
        .. table.concat(stderr)
        .. "\nEXIT "
        .. vim.inspect(exited)
        .. "\nMODE "
        .. vim.inspect(replies[sequence])
        .. "\n"
        .. table.concat(redraw, "\n")
    )
  end
  local reply = replies[id]
  if reply[3] ~= vim.NIL then error(vim.inspect(reply[3])) end
  return reply[4]
end
local function lua(code, ...) return rpc("nvim_exec_lua", code, { ... }) end
local function wait(code, message, timeout)
  local deadline = uv.hrtime() + (timeout or 10000) * 1000000
  while uv.hrtime() < deadline do
    if lua(code) then return end
    vim.wait(20)
  end
  local diagnostics = lua([[
    local info = {
      notifications = probe.notifications,
      adapters = require("neotest").state.adapter_ids(),
      current_filetype = vim.bo.filetype,
      messages = vim.fn.execute("messages"),
      configured_adapters = #require("neotest.config").adapters,
      windows = {},
      rust_positions = {},
      rust_clients = {},
      last_run = probe.last_run,
      last_results = probe.last_results,
      output = table.concat(vim.api.nvim_buf_get_lines(require("neotest").output_panel.buffer(), 0, -1, false), "\n"):sub(-6000),
    }
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      info.windows[#info.windows + 1] = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
    end
    for _, server in ipairs(vim.lsp.get_clients({name = "rust-analyzer"})) do
      info.rust_clients[#info.rust_clients + 1] = {root = server.config.root_dir, initialized = server.initialized}
    end
    for _, adapter in ipairs(info.adapters) do
      if adapter:match("^rustaceanvim:") then
        local tree = require("neotest").state.positions(adapter)
        if tree then
          for _, position in tree:iter() do
            info.rust_positions[#info.rust_positions + 1] = {
              name = position.name, id = position.id, type = position.type, runnable = position.runnable ~= nil,
            }
          end
        end
      end
    end
    local file = io.open(vim.fn.stdpath("log") .. "/neotest.log", "rb")
    if file then info.log = file:read("*a"):sub(-6000); file:close() end
    return vim.inspect(info)
  ]])
  error(message .. ": " .. table.concat(stderr) .. "\n" .. diagnostics)
end
local ok, failure = pcall(function()
  rpc("nvim_ui_attach", 140, 40, { rgb = true, ext_linegrid = true })
  lua(
    [[
    local root, temp = ...
    _G.fixture = temp
    vim.opt.rtp:prepend(root .. "/nvim")
    vim.o.loadplugins = true
    require("config.lazy")
    vim.g.dbs = vim.empty_dict()
    vim.g.db_ui_save_location = temp .. "/db-ui"
    vim.g.db_ui_tmp_query_location = temp .. "/queries"
    local config, plugin = require("lazy.core.config"), require("lazy.core.plugin")
    for _, name in ipairs({ "mason.nvim", "mason-lspconfig.nvim", "nvim-treesitter" }) do
      if config.plugins[name] then plugin.values(config.plugins[name], "opts", false).ensure_installed = {} end
    end
    _G.probe = { runs = 0, completed = 0, notifications = {}, run_ids = {} }
    local notify = vim.notify
    vim.notify = function(message, level, opts)
      if level and level >= vim.log.levels.ERROR then probe.notifications[#probe.notifications + 1] = message end
      return notify(message, level, opts)
    end
    local neotest = assert(config.plugins.neotest,
      "Neotest spec missing for " .. root .. "; loaded plugins: " .. table.concat(vim.tbl_keys(config.plugins), ", "))
    local user_opts = neotest.opts
    neotest.opts = function(plugin, opts)
      opts = user_opts(plugin, opts) or opts
      opts.consumers = vim.tbl_extend("force", opts.consumers or {}, {
        probe = function(client)
          probe.client = client
          client.listeners.run = function(_, id)
            probe.runs = probe.runs + 1
            probe.last_run = id
            probe.run_ids[#probe.run_ids + 1] = id
          end
          client.listeners.results = function(_, results, partial)
            if not partial then
              probe.completed = probe.completed + 1
              probe.last_results = results
            end
          end
        end,
      })
      return opts
    end
    _G.file_counts = function(path)
      local nt = require("neotest")
      for _, adapter in ipairs(nt.state.adapter_ids()) do
        local positions = nt.state.positions(adapter)
        local file = positions and positions:get_key(path)
        if file then
          local results = probe.client:get_results(adapter)
          local counts = { total = 0, passed = 0, failed = 0, skipped = 0 }
          for _, position in file:iter() do
            if position.type == "test" then
              counts.total = counts.total + 1
              local result = results[position.id]
              if result then counts[result.status] = (counts[result.status] or 0) + 1 end
            end
          end
          if counts.total > 0 then return counts end
        end
      end
      return { total = 0 }
    end
    _G.open_test = function(path, cwd)
      vim.cmd.tcd(cwd)
      vim.cmd.edit(path)
    end
    assert(not package.loaded.neotest, "Startup must not load Neotest or discover/build tests")
    assert(require("util.testing").statusline() == "")
    open_test(temp .. "/test_live.py", temp)
  ]],
    vim.fn.getcwd(),
    temp
  )
  rpc("nvim_input", " e")
  wait("return #Snacks.picker.get({source = 'explorer'}) == 1", "File Explorer must open before Test Explorer")
  rpc("nvim_input", " ts")
  wait("return require('neotest').state ~= nil", "Test Explorer key did not load Neotest")
  wait("return file_counts(fixture .. '/test_live.py').total == 4", "Python discovery failed", 15000)
  print("test view: discovery ready")
  lua([[
    local testing = require("util.testing")
    local file = fixture .. "/node/packages/library/example.test.ts"
    local adapter = testing.node_adapter("vitest")
    assert(adapter.root(file) == fixture .. "/node")
    assert(adapter.is_test_file(file), "Parent Vitest configuration must work across package boundaries")
    assert(not adapter.is_test_file(fixture .. "/node/packages/library/e2e/example.spec.ts"))
    assert(testing.node_root(fixture .. "/not-a-project/file.test.js", "jest") == nil)
    assert(not testing.filter_dir("API.FF.IntegrationTests"))
    local dotnet
    for _, candidate in ipairs(require("neotest.config").adapters) do
      if candidate.name == ".NET" then dotnet = candidate end
    end
    assert(dotnet)
    assert(dotnet.root(fixture .. "/first") == fixture .. "/first")
    assert(dotnet.root(fixture .. "/second") == fixture .. "/second")
    assert(dotnet.root(fixture .. "/first") == fixture .. "/first")
    _G.check_layout = function()
      assert(#Snacks.picker.get({source = "explorer"}) == 0, "Opening Test Explorer must close File Explorer")
      local summary, output
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
        if ft == "neotest-summary" then summary = win end
        if vim.api.nvim_win_get_buf(win) == require("neotest").output_panel.buffer() then output = win end
      end
      assert(summary and output, "Both test tree and output panel must be visible")
      assert(vim.api.nvim_win_get_position(summary)[2] == 0, "Test tree must be on the left")
      assert(vim.api.nvim_win_get_width(summary) < vim.o.columns / 2)
      assert(vim.api.nvim_win_get_position(output)[1] > 0, "Output must be below the code")
      assert(vim.api.nvim_win_get_position(output)[2] > vim.api.nvim_win_get_width(summary))
      assert(vim.api.nvim_win_get_height(summary) > vim.api.nvim_win_get_position(output)[1],
        "Test sidebar must retain its full height beside the output")
      assert(vim.api.nvim_win_get_width(output) + vim.api.nvim_win_get_width(summary) >= vim.o.columns - 3,
        "The test sidebar and output must use the available width")
    end
    check_layout()
  ]])
  rpc("nvim_ui_try_resize", 80, 40)
  lua("check_layout()")
  rpc("nvim_ui_try_resize", 140, 40)
  print("test view: layout and roots ready")
  rpc("nvim_input", " tt")
  wait(
    "return require('util.testing').statusline():find('running', 1, true) ~= nil",
    "Running tests must appear in the statusline"
  )
  wait(
    [[
    local icon = require("neotest.config").icons.running
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "neotest-summary" then
        return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find(icon, 1, true) ~= nil
      end
    end
    return false
  ]],
    "Running tests must have a visible status in the tree"
  )
  print("test view: running status visible")
  lua("_G.codewin = vim.api.nvim_get_current_win()")
  rpc("nvim_input", " ta")
  wait(
    [[
    local win = vim.api.nvim_get_current_win()
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "neotest-output" then return false end
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
    return table.concat(lines, "\n"):find("live test output", 1, true) ~= nil
  ]],
    "Attach must show live stdout before the test finishes"
  )
  print("test view: live output visible")
  lua("vim.fn.writefile({}, fixture .. '/release-live-test')")
  lua("vim.api.nvim_set_current_win(codewin)")
  wait(
    [[
    local c = file_counts(fixture .. "/test_live.py")
    return c.passed == 2 and c.failed == 1 and c.skipped == 1 and probe.completed > 0
  ]],
    "Python pass, failure, skip and unittest results must be reported correctly"
  )
  wait(
    [[
    local text = table.concat(vim.api.nvim_buf_get_lines(require("neotest").output_panel.buffer(), 0, -1, false), "\n")
    return text:find("expected fixture failure", 1, true) ~= nil
  ]],
    "Failure details must appear in the output panel"
  )
  print("test view: test results visible")
  lua([[
    _G.previous_tree_run = probe.completed
    require("neotest").summary:expand(fixture .. "/test_live.py", true)
  ]])
  wait(
    [[
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "neotest-summary" then
        for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
          if line:find("test_unittest_case", 1, true) then
            vim.api.nvim_set_current_win(win)
            vim.api.nvim_win_set_cursor(win, {row, 0})
            return true
          end
        end
      end
    end
    return false
  ]],
    "The test tree must expose the selected unittest case"
  )
  rpc("nvim_input", " tr")
  wait(
    [[
    return probe.completed > previous_tree_run and probe.last_run:match("::test_unittest_case$")
  ]],
    "Space t r in the test tree must run the selected test"
  )
  lua([[
    assert(probe.last_results[probe.last_run].status == "passed", "The selected tree test must pass")
    assert(not probe.last_results[fixture .. "/test_live.py::test_pass"],
      "Running a selected tree test must not run the rest of its file")
    assert(vim.bo.filetype == "neotest-summary", "Running from the tree must preserve sidebar focus")
    vim.api.nvim_set_current_win(codewin)
  ]])
  lua("open_test(fixture .. '/test_stop.py', fixture)")
  wait("return file_counts(fixture .. '/test_stop.py').total == 1", "Stop fixture discovery failed")
  rpc("nvim_input", " tt")
  wait(
    [[
    local lines = vim.api.nvim_buf_get_lines(require("neotest").output_panel.buffer(), 0, -1, false)
    return table.concat(lines, "\n"):find("test_stop.py::test_slow", 1, true) ~= nil
  ]],
    "Stop fixture must actually be running before cancellation"
  )
  rpc("nvim_input", " e")
  wait(
    [[
    if #Snacks.picker.get({source = "explorer"}) ~= 1 then return false end
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neotest-summary" then return false end
    end
    return true
  ]],
    "File Explorer must replace Test Explorer without stopping the run"
  )
  lua([[
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      assert(vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "neotest-summary")
    end
    assert(require("util.testing").statusline():find("running", 1, true), "Switching explorers must not stop tests")
    vim.api.nvim_set_current_win(codewin)
  ]])
  rpc("nvim_input", " tS")
  wait(
    "return require('util.testing').statusline():find('running', 1, true) == nil",
    "Stop did not finish the test run",
    5000
  )
  lua("assert(file_counts(fixture .. '/test_stop.py').passed == 0, 'Cancelled tests must not pass')")
  rpc("nvim_input", " e")
  rpc("nvim_input", " e")
  wait("return #Snacks.picker.get({source = 'explorer'}) == 1", "File Explorer must reopen normally")
  rpc("nvim_input", " ts")
  wait(
    [[
    if #Snacks.picker.get({source = "explorer"}) ~= 0 then return false end
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neotest-summary" then return true end
    end
    return false
  ]],
    "Test Explorer must reopen after File Explorer closes"
  )
  lua("check_layout()")
  rpc("nvim_input", " ts")
  lua([[
    _G.test_tab = vim.api.nvim_get_current_tabpage()
    vim.cmd.tabnew()
    Snacks.explorer({cwd = fixture})
  ]])
  wait("return #Snacks.picker.get({source = 'explorer'}) == 1", "Other tab's explorer must open")
  lua("vim.api.nvim_set_current_tabpage(test_tab)")
  rpc("nvim_input", " e")
  wait("return #Snacks.picker.get({source = 'explorer', tab = false}) == 2", "Each tab must have its own explorer")
  rpc("nvim_input", " ts")
  wait(
    [[
    if #Snacks.picker.get({source = "explorer"}) ~= 0 then return false end
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neotest-summary" then return true end
    end
    return false
  ]],
    "Test Explorer must open without affecting another tab"
  )
  lua([[
    check_layout()
    local explorers = Snacks.picker.get({source = "explorer", tab = false})
    assert(#explorers == 1 and not explorers[1]:on_current_tab(), "Other tab's explorer must remain open")
    explorers[1]:close()
  ]])
  lua([[
    _G.query = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(query, fixture .. "/sidebar-query.sql")
    vim.api.nvim_buf_set_lines(query, 0, -1, false, {"SELECT 'keep this query';"})
    vim.bo[query].filetype = "sql"
    _G.previous_code = vim.api.nvim_win_get_buf(codewin)
    vim.api.nvim_win_set_buf(codewin, query)
    _G.sidebar_counts = function()
      local counts = {tests = 0, files = #Snacks.picker.get({source = "explorer"}), database = 0}
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
        if ft == "neotest-summary" then counts.tests = counts.tests + 1 end
        if ft == "dbui" then counts.database = counts.database + 1 end
      end
      return counts
    end
    _G.open_sidebar = function(kind)
      if kind == "tests" then require("util.testing").open_view()
      elseif kind == "files" then Snacks.explorer({cwd = fixture})
      else vim.cmd.DBUI() end
    end
  ]])
  for _, kind in ipairs({ "tests", "files", "database", "tests", "database", "files", "tests" }) do
    lua("open_sidebar(...)", kind)
    wait(
      "local c = sidebar_counts(); return c." .. kind .. " == 1 and c.tests + c.files + c.database == 1",
      "Only the selected " .. kind .. " explorer must remain open"
    )
    lua([[
      assert(vim.api.nvim_buf_is_valid(query) and vim.bo[query].modified, "Sidebar switching must preserve unsaved SQL")
      assert(vim.api.nvim_buf_get_lines(query, 0, -1, false)[1] == "SELECT 'keep this query';")
    ]])
  end
  lua([[
    vim.api.nvim_set_current_win(codewin)
    vim.api.nvim_win_set_buf(codewin, previous_code)
    vim.cmd.DBUI()
    require("neotest").summary.open()
    vim.cmd.DBUI()
  ]])
  wait(
    "local c = sidebar_counts(); return c.database == 1 and c.tests == 0 and c.files == 0",
    "The last opened explorer must win for rapid commands"
  )
  lua("require('util.testing').open_view(); vim.api.nvim_set_current_win(codewin)")
  wait(
    "return file_counts(fixture .. '/rust/deep/library/src/lib.rs').total == 3",
    "Deep Rust tests must be discovered without opening the source",
    40000
  )
  lua([[
    open_test(fixture .. "/rust/deep/library/src/lib.rs", fixture)
    require("util.testing").run_file()
  ]])
  wait(
    [[
    local c = file_counts(fixture .. '/rust/deep/library/src/lib.rs')
    return c.passed == 2 and c.failed == 1
  ]],
    "Cargo must run both modules and report the deliberate failure",
    40000
  )
  wait(
    "return file_counts(fixture .. '/rust/other/library/src/lib.rs').total == 1",
    "A second Cargo project must be discovered in the same workspace",
    40000
  )
  lua("open_test(fixture .. '/rust/other/library/src/lib.rs', fixture); require('util.testing').run_file()")
  wait(
    "return file_counts(fixture .. '/rust/other/library/src/lib.rs').passed == 1",
    "A second Cargo project's unit tests must pass",
    40000
  )
  lua([[
    _G.previous_bulk_completion = probe.completed
    _G.previous_bulk_runs = #probe.run_ids
    require("neotest").summary:expand(fixture .. "/rust", false)
  ]])
  wait(
    [[
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "neotest-summary" then
        for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
          if line:match("rust%s*$") then
            vim.api.nvim_set_current_win(win)
            vim.api.nvim_win_set_cursor(win, {row, 0})
            return true
          end
        end
      end
    end
    return false
  ]],
    "The mixed-language folder must be selectable in the tree"
  )
  rpc("nvim_input", " tr")
  wait(
    [[
    return probe.completed >= previous_bulk_completion + 3
      and file_counts(fixture .. "/rust/test_workspace.py").passed == 1
  ]],
    "Running a tree folder must execute Python and both Cargo projects",
    40000
  )
  lua([[
    local expected = {
      [fixture .. "/rust"] = true,
      [fixture .. "/rust/deep/library"] = true,
      [fixture .. "/rust/other/library"] = true,
    }
    assert(#probe.run_ids == previous_bulk_runs + 3, "Folder selection must run each language root once")
    for index = previous_bulk_runs + 1, #probe.run_ids do
      local id = probe.run_ids[index]
      assert(expected[id], "Folder run escaped the selected directory")
      expected[id] = nil
    end
    assert(next(expected) == nil, "Folder run omitted a language project")
    _G.previous_rerun_completion = probe.completed
    _G.previous_rerun_runs = #probe.run_ids
  ]])
  rpc("nvim_input", " tl")
  wait(
    "return probe.completed >= previous_rerun_completion + 3",
    "Rerun must preserve the complete mixed-language folder selection",
    40000
  )
  lua([[
    assert(#probe.run_ids == previous_rerun_runs + 3, "Folder rerun must include every language root once")
    _G.previous_cancel_completion = probe.completed
    _G.previous_cancel_runs = #probe.run_ids
    vim.fn.writefile({}, fixture .. "/rust/hold-workspace-tests")
  ]])
  rpc("nvim_input", " tl")
  wait(
    [[
    local output = table.concat(vim.api.nvim_buf_get_lines(require("neotest").output_panel.buffer(), 0, -1, false), "\n")
    return probe.last_run == fixture .. "/rust" and output:find("workspace test waiting", 1, true) ~= nil
  ]],
    "Folder cancellation must wait for the real test process"
  )
  wait(
    [[
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "neotest-summary" then
        for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
          if line:match("rust%s*$") then
            vim.api.nvim_set_current_win(win)
            vim.api.nvim_win_set_cursor(win, {row, 0})
            return true
          end
        end
      end
    end
    return false
  ]],
    "The running folder must remain selectable"
  )
  rpc("nvim_input", " tS")
  wait(
    [[
    return probe.completed > previous_cancel_completion
      and not require("util.testing").statusline():find("running", 1, true)
  ]],
    "Stopping a folder must finish its active process",
    5000
  )
  lua([[
    assert(#probe.run_ids == previous_cancel_runs + 1, "Stopping a folder must not launch remaining projects")
    vim.fn.delete(fixture .. "/rust/hold-workspace-tests")
    _G.previous_header_completion = probe.completed
    vim.api.nvim_set_current_win(codewin)
  ]])
  wait(
    [[
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "neotest-summary" then
        for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
          if line == "rust/deep/library" then
            vim.api.nvim_set_current_win(win)
            vim.api.nvim_win_set_cursor(win, {row, 0})
            return true
          end
        end
      end
    end
    return false
  ]],
    "The Cargo project header must be selectable"
  )
  rpc("nvim_input", "r")
  wait(
    [[
    return probe.completed > previous_header_completion and probe.last_run == fixture .. "/rust/deep/library"
  ]],
    "r on a project header must execute that project's tests",
    40000
  )
  lua("vim.api.nvim_set_current_win(codewin)")
  print("test view: all sidebar transitions and Rust execution passed")
  if vim.env.NVIM_TEST_KAS then
    local kas = vim.env.NVIM_TEST_KAS
    lua(
      [[
      local kas = ...
      _G.kas_workspace = kas
      vim.cmd.tcd(kas)
      vim.cmd("TestView " .. vim.fn.fnameescape(kas))
      _G.workspace_stats = function()
        local files, tests, projects = {}, {}, {}
        local counts = {cs = 0, js = 0, ts = 0, projects = 0, files = 0}
        for _, adapter in ipairs(require("neotest").state.adapter_ids()) do
          local tree = require("neotest").state.positions(adapter)
          if tree then
            for _, position in tree:iter() do
              if position.type == "test" and vim.fs.relpath(kas, position.path) and not tests[position.id] then
                tests[position.id] = true
                local extension = position.path:match("%.([^.]+)$")
                if counts[extension] then counts[extension] = counts[extension] + 1 end
                files[position.path] = true
                if extension == "cs" then
                  local project = require("neotest.lib").files.match_root_pattern("*.csproj")(position.path)
                  projects[project] = true
                end
                assert(not position.path:find("/e2e/", 1, true), "E2E tests must not enter unit discovery")
                assert(not position.path:find(".IntegrationTests/", 1, true), "Integration projects must remain excluded")
              end
            end
          end
        end
        counts.files, counts.projects = vim.tbl_count(files), vim.tbl_count(projects)
        return counts
      end
    ]],
      kas
    )
    wait(
      "return require('neotest').test_workspace.is_complete(kas_workspace)",
      "KAS project discovery must finish",
      90000
    )
    wait(
      "local c = workspace_stats(); return c.projects >= 9 and c.cs > 6 and c.js > 2 and c.ts > 2",
      "KAS backend and deep frontend tests must be discovered together",
      90000
    )
    print("KAS: combined discovery " .. lua("return vim.inspect(workspace_stats())"))
    lua([[
      local workspace = require("neotest").test_workspace
      local execute = workspace.run_directory
      _G.kas_folder_runs = {}
      _G.kas_folder_execute = execute
      workspace.run_directory = function(path, args, run)
        _G.kas_selected_directory = path
        return execute(path, args, function(selection)
          kas_folder_runs[#kas_folder_runs + 1] = selection
        end)
      end
      vim.cmd.tcd(vim.fs.dirname(kas_workspace))
      require("neotest").summary.render()
    ]])
    wait(
      [[
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == "neotest-summary" then
          for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
            if line == "KAS" then
              vim.api.nvim_set_current_win(win)
              vim.api.nvim_win_set_cursor(win, {row, 0})
              return true
            end
          end
        end
      end
      return false
    ]],
      "The KAS workspace header must be selectable"
    )
    rpc("nvim_input", " tr")
    wait("return #kas_folder_runs >= 2", "Selecting KAS must target all backend and frontend test roots")
    lua([[
      require("neotest").test_workspace.run_directory = kas_folder_execute
      assert(kas_selected_directory == kas_workspace, "The KAS row must resolve to the real workspace directory")
      local selected, count = {}, 0
      for _, run in ipairs(kas_folder_runs) do
        local tree = require("neotest").state.positions(run.adapter):get_key(run[1])
        for _, position in tree:iter() do
          if position.type == "test" then
            assert(vim.fs.relpath(kas_workspace, position.path), "KAS selection must not run fixture projects")
            assert(not selected[position.id] or selected[position.id] == run.adapter,
              "KAS selection must not repeat a test across runners")
            if not selected[position.id] then
              selected[position.id], count = run.adapter, count + 1
            end
          end
        end
      end
      local all = workspace_stats()
      assert(count == all.cs + all.js + all.ts, "The KAS row must include every discovered C#/JS/TS test")
      vim.api.nvim_set_current_win(codewin)
    ]])
    print("KAS: workspace row targets every C#/JS/TS test without executing the full suite")
    for _, case in ipairs({
      { "/frontend/kas-app", "/packages/core/test/unit/utils.pagination.test.js", 2 },
      { "/frontend/kas-app", "/packages/core/test/unit/utils.api.resourcePermissions.test.ts", 2 },
      { "/backend", "/tests/KAS.App/API.SlaReport.UnitTests/SlaReportControllerTests.cs", 6 },
    }) do
      local cwd, path = kas .. case[1], kas .. case[1] .. case[2]
      lua(
        "local path, cwd = ...; _G.kas_test = path; vim.lsp.enable('roslyn_ls', false); open_test(path, cwd); require('util.testing').open_view()",
        path,
        cwd
      )
      print("KAS: discovering " .. case[2])
      wait("return file_counts(kas_test).total > 0", "KAS test discovery failed for " .. path, 30000)
      lua("assert(file_counts(kas_test).total >= ..., 'KAS tests were missing from discovery')", case[3])
      rpc("nvim_input", " tt")
      wait(
        [[
        local c = file_counts(kas_test)
        return c.total > 0 and c.passed + c.failed + c.skipped == c.total
      ]],
        "KAS results never completed for " .. path,
        90000
      )
      lua([[
        local c = file_counts(kas_test)
        local output = table.concat(vim.api.nvim_buf_get_lines(require("neotest").output_panel.buffer(), 0, -1, false), "\n")
        local file = io.open(vim.fn.stdpath("log") .. "/neotest.log", "rb")
        local log = file and file:read("*a"):sub(-4000) or ""
        if file then file:close() end
        assert(c.failed == 0 and c.passed == c.total,
          "KAS unit tests did not pass: " .. vim.inspect(c) .. "\n" .. output:sub(-8000) .. "\n" .. log)
      ]])
      print("KAS: " .. case[2] .. " passed through Neotest")
      if case[1] == "/backend" then
        lua([[
          local output = table.concat(vim.api.nvim_buf_get_lines(require("neotest").output_panel.buffer(), 0, -1, false), "\n")
          assert(output:match("\n%s*total:%s*(%d+)") == "6", "Run-file must execute only the six selected tests")
          _G.nearest_test = nil
          for _, adapter in ipairs(require("neotest").state.adapter_ids()) do
            local positions = require("neotest").state.positions(adapter)
            local file = positions and positions:get_key(kas_test)
            if file then
              for _, position in file:iter() do
                if position.type == "test" then
                  if nearest_test then
                    _G.other_test = position.id
                    return
                  else
                    _G.nearest_test = position.id
                    _G.previous_completion = probe.completed
                    vim.api.nvim_win_set_cursor(0, {position.range[1] + 1, 0})
                  end
                end
              end
            end
          end
          error("No C# test available for nearest-test validation")
        ]])
        rpc("nvim_input", " tr")
        wait(
          [[
          return probe.completed > previous_completion
            and probe.last_results[nearest_test]
            and not probe.last_results[other_test]
        ]],
          "Nearest C# test did not finish",
          90000
        )
        wait(
          [[
          local output = table.concat(vim.api.nvim_buf_get_lines(require("neotest").output_panel.buffer(), 0, -1, false), "\n")
          return output:match("\n%s*total:%s*(%d+)") == "1"
        ]],
          "Run-nearest must execute exactly one C# test"
        )
        lua([[
          assert(probe.last_run == nearest_test, "Run-nearest selected the wrong C# test")
          assert(probe.last_results[nearest_test].status == "passed", "Nearest C# result must pass through the adapter")
          assert(file_counts(kas_test).failed == 0 and file_counts(kas_test).passed == 6)
        ]])
        print("KAS: nearest C# test passed without running other methods")
      end
    end
  end
  lua("assert(#probe.notifications == 0, table.concat(probe.notifications, '\\n'))")
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
print("test view: live status/output, results, cancellation, layout and workspace roots passed")
vim.cmd("qa!")
