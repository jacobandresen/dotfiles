-- Run: timeout 60 nvim --headless -u NONE -i NONE -l nvim/tests/pi_issues.lua
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local core = require("util.pi_issues")
local ui = require("util.pi_issues_ui")
local uv = vim.uv
local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. "/repo", "p")
vim.g.pi_issues = {
  state_dir = temp .. "/state", pi = vim.fn.getcwd() .. "/nvim/tests/fixtures/pi_stub.py", github_enabled = true,
}
local messages = {}
vim.notify = function(message) messages[#messages + 1] = tostring(message) end
_G.LazyVim = { root = setmetatable({ detectors = {}, cache = {} }, { __call = function() return temp .. "/repo" end }) }
local function cmd(args, cwd)
  local result = vim.system(args, { cwd = cwd or temp .. "/repo", text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end
local function git(...) return cmd(vim.list_extend({ "git" }, { ... })) end
local function write(path, lines) vim.fn.writefile(lines, path) end
local function await(fn)
  local done, failure, result = false
  core.task(function()
    local ok, value = pcall(fn)
    if ok then
      result = value
    else
      failure = value
    end
    done = true
  end)
  assert(vim.wait(15000, function() return done end, 10), "Timed out: " .. table.concat(messages, "\n"))
  assert(not failure, failure)
  return result
end
local function expect_error(fn, pattern)
  local ok, err = pcall(fn)
  assert(not ok and tostring(err):find(pattern, 1, true), "Expected " .. pattern .. ", got " .. tostring(err))
end

local ok, failure = pcall(function()
  git("init", "-b", "main")
  git("config", "user.email", "test@example.invalid")
  git("config", "user.name", "Test")
  write(temp .. "/repo/same name.txt", { "original" })
  write(temp .. "/repo/rename.txt", { "rename me" })
  git("add", ".")
  git("commit", "-m", "Initial")
  local sha = git("rev-parse", "HEAD")
  local repo = { root = temp .. "/repo", common = temp .. "/repo/.git", repo = "test/repo", host = "github.com" }
  write(temp .. "/repo/dirty.txt", { "keep main dirty" })
  local a = await(function() return core.prepare(repo, { number = 11, title = "First % issue" }, "main") end)
  local b = await(function() return core.prepare(repo, { number = 12, title = "Second issue" }, "main") end)
  assert(a.id ~= b.id and a.path ~= b.path and a.session ~= b.session, "Issue identity must be isolated")
  assert(a.base_sha == sha and uv.fs_stat(temp .. "/repo/dirty.txt"), "Preserve dirty main checkout")
  assert(await(function() return core.prepare(repo, { number = 11, title = "First" }, "main", true) end) == a)
  await(function()
    core.validate(a)
    core.validate(b)
  end)
  core.setup()
  core.open(a)
  local tab_a = vim.api.nvim_get_current_tabpage()
  core.open(b)
  local tab_b = vim.api.nvim_get_current_tabpage()
  assert(core.current() == b and vim.fn.getcwd() == b.path)
  core.open(a)
  assert(vim.api.nvim_get_current_tabpage() == tab_a and core.root() == a.path)
  assert(#vim.api.nvim_list_tabpages() == 3, "Duplicate opens must reuse their tab")
  assert(core.inside(a.path .. "/same name.txt", a.path))
  assert(not core.inside(b.path .. "/same name.txt", a.path))
  uv.fs_symlink(b.path .. "/same name.txt", a.path .. "/outside")
  assert(not core.inside(a.path .. "/outside", a.path), "Resolve symlinks before sending")
  uv.fs_unlink(a.path .. "/outside")
  assert(uv.fs_symlink(b.path, a.path .. "/outside-dir"))
  assert(
    not core.inside(a.path .. "/outside-dir/not-saved-yet.txt", a.path),
    "Unsaved files below a symlink must still belong to the correct worktree"
  )
  uv.fs_unlink(a.path .. "/outside-dir")

  write(a.path .. "/same name.txt", { "staged" })
  cmd({ "git", "add", "same name.txt" }, a.path)
  write(a.path .. "/same name.txt", { "unstaged" })
  write(a.path .. "/new\r\nfile.txt", { "untracked" })
  cmd({ "git", "mv", "rename.txt", "renamed file.txt" }, a.path)
  local rows = await(function() return core.files(a, "working") end)
  assert(#rows == 4, vim.inspect(rows))
  local staged, unstaged, untracked, renamed = false, false, false, false
  for _, row in ipairs(rows) do
    if row.file == "same name.txt" then
      if row.staged then
        staged = true
      else
        unstaged = true
      end
    end
    untracked = untracked or row.file == "new\r\nfile.txt"
    renamed = renamed or row.old == "rename.txt"
  end
  assert(staged and unstaged and untracked and renamed, "Diff scopes must preserve stages, renames and unusual paths")
  await(function() core.refresh(a) end)
  assert(a.files == 3, "Count a renamed file once")
  local done_refreshing, real_run = false, core.run
  core.run = function(argv, cwd, ...)
    if argv[2] ~= "status" then return real_run(argv, cwd, ...) end
    core.run = real_run
    -- Snapshot the worktree now, but answer later: the agent's write lands in between.
    local stale = vim.system(argv, { cwd = cwd }):wait()
    local thread = coroutine.running()
    vim.defer_fn(function() coroutine.resume(thread, stale) end, 200)
    return coroutine.yield()
  end
  core.task(function() core.refresh(a) done_refreshing = true end)
  write(a.path .. "/late-agent-write.txt", { "written after the first git status started" })
  await(function() core.refresh(a) end)
  assert(vim.wait(5000, function() return done_refreshing and not a.refreshing end, 10))
  assert(a.files == 4, "A refresh requested during another must still count later writes: " .. tostring(a.files))
  assert(uv.fs_unlink(a.path .. "/late-agent-write.txt"))
  await(function() core.refresh(a) end)
  assert(a.files == 3)
  cmd({ "git", "commit", "-m", "Issue change" }, a.path)
  local issue_rows = await(function() return core.files(a, "issue") end)
  assert(#issue_rows == 3, "Issue scope includes committed changes")
  cmd({ "git", "worktree", "lock", a.path }, repo.root)
  await(function()
    expect_error(function() core.validate(a) end, "locked")
  end)
  cmd({ "git", "worktree", "unlock", a.path }, repo.root)

  await(function()
    expect_error(function() core.start(a, { body = string.rep("x", 100001) }) end, "too large")
  end)
  assert(not uv.fs_stat(core.directory(a) .. "/owner.json"), "Failed launch must not leak ownership")
  local original_jobstart = vim.fn.jobstart
  vim.fn.jobstart = function() error("simulated spawn failure") end
  await(function()
    expect_error(function() core.start(a, { body = "Test" }) end, "simulated spawn failure")
  end)
  vim.fn.jobstart = original_jobstart
  assert(
    core.jobs[a.id].exited and not uv.fs_stat(core.directory(a) .. "/owner.json"),
    "Spawn errors release ownership"
  )
  local owner_file = core.directory(a) .. "/owner.json"
  core.write(owner_file, vim.json.encode({ pid = 999999999, token = "abandoned" }))
  local choose = core.choose
  core.choose = function()
    core.write(owner_file, vim.json.encode({ pid = vim.fn.getpid(), token = "other-editor" }))
    return "Recover abandoned lock"
  end
  await(function()
    expect_error(function() core.lock(a, "test") end, "owner changed during recovery")
  end)
  core.choose = choose
  assert(
    vim.json.decode(table.concat(vim.fn.readfile(owner_file))).token == "other-editor",
    "A late recovery confirmation must not unlink a replacement owner"
  )
  assert(not uv.fs_stat(owner_file .. ".recovery"))
  assert(uv.fs_unlink(owner_file))
  vim.env.NVIM_PI_TEST_CHILD = "1"
  await(function() core.start(a, { body = "Test issue. Do not call a model." }) end)
  vim.env.NVIM_PI_TEST_CHILD = nil
  local job = core.jobs[a.id]
  assert(not vim.tbl_contains(job.argv, "--provider") and not vim.tbl_contains(job.argv, "--model"),
    "New issue sessions must inherit pi-agent's configured default")
  assert(job.channel > 0 and not job.exited)
  assert(vim.wait(5000, function() return job.sequence ~= nil end, 10), table.concat(messages, "\n"))
  assert(job.activity == "idle" and a.session_file, "Consume real filesystem lifecycle notifications")
  assert(job.model == "ollama/mellum", "Display the model reported by pi-agent")
  local first_job = job.channel
  await(function() core.start(a) end)
  assert(core.jobs[a.id].channel == first_job, "Never start a second writer")
  expect_error(function() core.lock(a, "another") end, "owned")
  local snapshot = {
    version = 1,
    run = job.run,
    sequence = 10,
    cwd = a.path,
    session = a.session,
    session_file = a.session_file,
    activity = "working",
    model = "github-copilot/gpt-6.1-sol",
  }
  assert(core.accept_status(a, job, snapshot))
  assert(not core.accept_status(a, job, snapshot), "Reject out-of-order events")
  snapshot.run, snapshot.sequence = "old-run", 11
  assert(not core.accept_status(a, job, snapshot), "Reject stale process events")
  core.open(b)
  assert(core.jobs[a.id].activity == "working" and core.current() == b, "Late updates must not retarget current tab")
  local source = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_win_set_buf(0, source)
  vim.api.nvim_buf_set_name(source, b.path .. "/same name.txt")
  vim.api.nvim_buf_set_lines(source, 0, -1, false, { "second issue unsaved" })
  require("util.agents").send(false)
  assert(not core.jobs[b.id], "Sending without pi must never create a job")
  core.open(a)
  vim.api.nvim_win_set_buf(0, source)
  require("util.agents").send(false)
  assert(messages[#messages]:find("outside"), "Reject context from another worktree")
  local own = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_win_set_buf(0, own)
  vim.api.nvim_buf_set_name(own, a.path .. "/same name.txt")
  vim.api.nvim_buf_set_lines(own, 0, -1, false, { "first issue unsaved" })
  require("util.agents").send(false)
  assert(
    vim.wait(3000, function()
      local path = core.directory(a) .. "/paste.txt"
      return uv.fs_stat(path) and table.concat(vim.fn.readfile(path), "\n"):find("first issue unsaved", 1, true)
    end, 10),
    "Bracketed context must reach the correct pi"
  )
  local pasted = table.concat(vim.fn.readfile(core.directory(a) .. "/paste.txt"), "\n")
  assert(pasted:find("unsaved buffer snapshot", 1, true))
  assert(not pasted:find("second issue", 1, true))
  local model = job.model
  job.model = nil
  require("util.agents").review()
  assert(messages[#messages]:find("active model", 1, true), "Do not guess a reviewer model before status arrives")
  job.model = model
  local send = vim.api.nvim_chan_send
  local review
  vim.api.nvim_chan_send = function(channel, text)
    assert(channel == job.channel, "Send the reviewer request to the current issue")
    review = text
  end
  require("util.agents").review()
  vim.api.nvim_chan_send = send
  assert(review and review:find("model: github-copilot/gpt-6.1-sol", 1, true),
    "Reviewers must follow the active session model")
  require("util.agents").toggle()
  assert(not job.exited and vim.fn.jobwait({ job.channel }, 0)[1] == -1, "Hiding terminal must not stop pi")
  core.show(a)
  core.open(b)
  await(function() core.start(b, { body = "Second issue" }) end)
  assert(vim.wait(3000, function() return core.jobs[b.id].sequence ~= nil end, 10))
  core.stop(a)
  assert(vim.wait(4000, function() return job.exited end, 10))
  local child_pid = tonumber(vim.fn.readfile(core.directory(a) .. "/child.pid")[1])
  local function child_running()
    local fd = uv.fs_open("/proc/" .. child_pid .. "/stat", "r", 0)
    if not fd then return false end
    local stat = uv.fs_read(fd, 4096, 0)
    uv.fs_close(fd)
    return stat and stat:match("^%d+ %b() (%a)") ~= "Z"
  end
  local child_stopped = vim.wait(2000, function() return not child_running() end, 10)
  if not child_stopped then uv.kill(child_pid, 15) end
  assert(child_stopped, "Stopping pi must terminate its ordinary child commands")
  assert(not core.jobs[b.id].exited, "Stopping one issue must leave another running")
  assert(not uv.fs_stat(core.directory(a) .. "/owner.json"), "Release ownership after process exit")
  snapshot.run, snapshot.sequence = job.run, 100
  assert(not core.accept_status(a, job, snapshot), "Exited process is authoritative")
  await(function() core.start(a) end)
  local resumed = core.jobs[a.id]
  assert(
    vim.tbl_contains(resumed.argv, "--session") and not vim.tbl_contains(resumed.argv, "Implement the attached task."),
    "Resume the exact session without replaying the initial task"
  )
  core.stop(a)
  core.stop(b)
  assert(vim.wait(4000, function() return resumed.exited and core.jobs[b.id].exited end, 10))
  local c = await(function() return core.prepare(repo, { number = 21, title = "Concurrent one" }, "main") end)
  local d = await(function() return core.prepare(repo, { number = 22, title = "Concurrent two" }, "main") end)
  local run = core.run
  core.run = function(argv, ...)
    if argv[1] == "gh" then
      local thread = coroutine.running()
      vim.defer_fn(
        function() assert(coroutine.resume(thread, { code = 0, stdout = '{"body":"Concurrent test"}' })) end,
        30
      )
      return coroutine.yield()
    end
    return run(argv, ...)
  end
  local settings = vim.g.pi_issues
  vim.g.pi_issues = vim.tbl_extend("force", settings, { max_agents = 1 })
  local attempts = {}
  for _, workspace in ipairs({ c, d }) do
    core.task(function()
      local started, reason = pcall(core.start, workspace)
      attempts[workspace.id] = { started = started, reason = reason }
    end)
  end
  assert(vim.wait(5000, function() return vim.tbl_count(attempts) == 2 end, 10), "Concurrent launches did not finish")
  core.run, vim.g.pi_issues = run, settings
  assert(attempts[c.id].started ~= attempts[d.id].started, "Concurrent launches must obey the live agent cap")
  for _, workspace in ipairs({ c, d }) do
    core.stop(workspace)
  end
  assert(vim.wait(4000, function()
    for _, workspace in ipairs({ c, d }) do
      if core.jobs[workspace.id] and not core.jobs[workspace.id].exited then return false end
    end
    return true
  end, 10))
  local restored = dofile(vim.fs.dirname(core.path()) .. "/lua/util/pi_issues.lua")
  restored.load()
  assert(restored.workspaces[a.id].session_file == a.session_file, "Restore exact persisted session")
  assert(next(restored.jobs) == nil, "Loading saved workspaces must not start agents")
  local snacks = vim.fn.stdpath("data") .. "/lazy/snacks.nvim"
  if uv.fs_stat(snacks) then
    vim.opt.rtp:append(snacks)
    _G.Snacks = require("snacks")
    Snacks.setup({ picker = { enabled = true }, notifier = { enabled = false } })
    vim.o.showtabline = 0
    for _, width in ipairs({ vim.o.columns }) do
      ui.review(a)
      assert(
        vim.wait(5000, function()
          local pickers = Snacks.picker.get()
          local picker = pickers[1]
          if not picker or not picker.preview.win:valid() then return false end
          local lines = vim.api.nvim_buf_get_lines(picker.preview.win.buf, 0, -1, false)
          return table.concat(lines, "\n"):find("diff --git", 1, true) ~= nil
        end, 10),
        "Diff preview did not render: " .. table.concat(messages, "\n")
      )
      local picker = Snacks.picker.get()[1]
      local preview = vim.api.nvim_win_get_position(picker.preview.win.win)
      local list = vim.api.nvim_win_get_position(picker.list.win.win)
      assert(
        preview[2] + vim.api.nvim_win_get_width(picker.preview.win.win) <= list[2],
        "Diff must be left of the selector without overlap"
      )
      assert(vim.api.nvim_win_get_width(picker.preview.win.win) > vim.api.nvim_win_get_width(picker.list.win.win))
      picker:close()
      vim.wait(100)
    end
  end
  local original_input, original_choose = core.input, ui.confirm_launch
  core.input = function() return "main" end
  local moved_sha = cmd({ "git", "rev-parse", "HEAD" }, a.path)
  ui.confirm_launch = function()
    git("update-ref", "refs/heads/main", moved_sha)
    return "Prepare only"
  end
  ui.launch(
    repo,
    { { number = 11, title = "Existing" }, { number = -1, title = "Invalid" }, { number = 13, title = "Third" } },
    { review = true }
  )
  assert(
    vim.wait(
      5000,
      function() return messages[#messages] and messages[#messages]:find("2 prepared; 0 started", 1, true) end,
      10
    ),
    "Batch must continue after a partial failure: " .. table.concat(messages, "\n")
  )
  assert(messages[#messages]:find("Invalid issue number", 1, true))
  for _, workspace in pairs(core.workspaces) do
    if workspace.number == 13 then
      assert(workspace.base_sha == sha, "Launch must use the exact base SHA shown before confirmation")
    end
  end
  git("update-ref", "refs/heads/main", sha)
  core.input, ui.confirm_launch = original_input, original_choose
  local confirmation
  core.task(function() confirmation = ui.confirm_launch({ "test/repo", "Cancel must not launch anything." }) end)
  local confirmation_buf = vim.api.nvim_get_current_buf()
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(confirmation_buf, "n")) do
    if mapping.lhs == "q" then mapping.callback() end
  end
  assert(vim.wait(1000, function() return confirmation == "Cancel" end, 10), "Launch preview must support cancellation")
  for _, current in pairs(core.jobs) do
    assert(current.exited, "Prepare-only must not launch")
  end
  ui.dashboard()
  local panel = vim.api.nvim_get_current_win()
  assert(vim.api.nvim_win_get_config(panel).relative == "editor", "Dashboard is a compact floating panel")
  assert(vim.wo.cursorline and vim.wo.signcolumn == "no")
  assert(#vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, {}) > 0, "Dashboard uses restrained semantic highlighting")
  vim.api.nvim_win_close(panel, true)
  assert(vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true }).str:find("repo#"))
  assert(vim.api.nvim_tabpage_is_valid(tab_b) and uv.fs_stat(a.path), "Closing the panel preserves tabs/worktrees")
end)

for id, job in pairs(core.jobs) do
  if not job.exited then core.stop(core.workspaces[id]) end
end
vim.wait(3000, function()
  for _, job in pairs(core.jobs) do
    if not job.exited then return false end
  end
  return true
end, 10)
vim.fn.delete(temp, "rf")
if not ok then
  io.stderr:write(tostring(failure) .. "\n")
  vim.cmd("cquit 1")
end
print("pi issues: routing, Git scopes, lifecycle, context, stop/resume and dashboard passed")
vim.cmd("qa!")
