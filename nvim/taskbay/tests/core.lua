-- Run: timeout 60 nvim --headless -u NONE -i NONE -l tests/core.lua
local plugin = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(plugin)
vim.g.mapleader = " "
local core = require("taskbay.core")
local ui = require("taskbay.ui")
local uv = vim.uv
local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. "/repo", "p")
vim.g.taskbay = {
  state_dir = temp .. "/state", pi = { cmd = plugin .. "/tests/fixtures/pi_stub.py" }, remote_enabled = true,
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
  -- LazyVim's root is the task's worktree first.
  assert(vim.g.root_spec[1] == "taskbay" and LazyVim.root.detectors.taskbay()[1] == b.path, vim.inspect(vim.g.root_spec))
  -- Hints name the configured keys with the configured leader.
  assert(core.key("toggle") == "F6" and core.key("panel") == "Space a w", core.key("panel"))
  local settings = vim.g.taskbay
  vim.g.taskbay, vim.g.mapleader = vim.tbl_extend("force", settings, { keys = { panel = "<leader>tw" } }), ","
  assert(core.key("panel") == ", t w" and core.key("new") == ", a n", core.key("panel"))
  vim.g.taskbay, vim.g.mapleader = settings, " "
  -- The plugin entry point: setup stores options, the statusline names the task tab's agent.
  -- Without LazyVim the root outside task tabs is the buffer's Git root.
  local lazyvim, tab = _G.LazyVim, vim.api.nvim_get_current_tabpage()
  vim.cmd.tabnew(vim.fn.fnameescape(temp .. "/repo/README.md"))
  _G.LazyVim = nil
  assert(core.root() == temp .. "/repo", core.root())
  _G.LazyVim = lazyvim
  vim.cmd.tabclose()
  vim.api.nvim_set_current_tabpage(tab)
  local taskbay = require("taskbay")
  assert(taskbay.statusline():find("Pi ", 1, true), taskbay.statusline())
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
  -- choose: a multi-line prompt is titled by its first line and shows the rest above the choices.
  local select, seen = vim.ui.select, {}
  vim.ui.select = function(items, opts, on_choice) seen[#seen + 1] = opts; on_choice(items[2]) end
  local preview_lines
  await(function()
    assert(core.choose({ "Cancel", "Go" }, "One line") == "Go")
    assert(core.choose({ "Cancel", "Go" }, "Title\n\nFirst detail\nSecond detail\n") == "Go")
  end)
  vim.ui.select = select
  assert(seen[1].prompt == "One line" and not seen[1].snacks, "Single-line prompts pass through")
  assert(seen[2].snacks.preview({ preview = { set_lines = function(_, l) preview_lines = l end } }))
  assert(seen[2].prompt == "Title" and vim.deep_equal(preview_lines, { "First detail", "Second detail" })
    and seen[2].snacks.layout.layout.height == 2 + 2 + 5, "Details show above the choices")
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
  require("taskbay.terminal").send(false)
  assert(not core.jobs[b.id], "Sending without pi must never create a job")
  core.open(a)
  vim.api.nvim_win_set_buf(0, source)
  require("taskbay.terminal").send(false)
  assert(messages[#messages]:find("outside"), "Reject context from another worktree")
  local own = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_win_set_buf(0, own)
  vim.api.nvim_buf_set_name(own, a.path .. "/same name.txt")
  vim.api.nvim_buf_set_lines(own, 0, -1, false, { "first issue unsaved" })
  require("taskbay.terminal").send(false)
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
  require("taskbay.terminal").review()
  assert(messages[#messages]:find("active model", 1, true), "Do not guess a reviewer model before status arrives")
  job.model = model
  local send = vim.api.nvim_chan_send
  local review
  vim.api.nvim_chan_send = function(channel, text)
    assert(channel == job.channel, "Send the reviewer request to the current issue")
    review = text
  end
  require("taskbay.terminal").review()
  vim.api.nvim_chan_send = send
  assert(review and review:find("model: github-copilot/gpt-6.1-sol", 1, true),
    "Reviewers must follow the active session model")
  require("taskbay.terminal").toggle()
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
  local settings = vim.g.taskbay
  vim.g.taskbay = vim.tbl_extend("force", settings, { max_agents = 1 })
  local attempts = {}
  for _, workspace in ipairs({ c, d }) do
    core.task(function()
      local started, reason = pcall(core.start, workspace)
      attempts[workspace.id] = { started = started, reason = reason }
    end)
  end
  assert(vim.wait(5000, function() return vim.tbl_count(attempts) == 2 end, 10), "Concurrent launches did not finish")
  core.run, vim.g.taskbay = run, settings
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
  local restored = dofile(vim.api.nvim_get_runtime_file("lua/taskbay/core.lua", false)[1])
  restored.load()
  assert(restored.workspaces[a.id].session_file == a.session_file, "Restore exact persisted session")
  assert(next(restored.jobs) == nil, "Loading saved workspaces must not start agents")
  local snacks = (vim.env.TASKBAY_SNACKS or (vim.fn.stdpath("data") .. "/lazy/snacks.nvim"))
  if uv.fs_stat(snacks) then
    vim.opt.rtp:append(snacks)
    _G.Snacks = require("snacks")
    Snacks.setup({ picker = { enabled = true }, notifier = { enabled = false } })
    vim.o.showtabline = 0
    for _, width in ipairs({ vim.o.columns }) do
      require("taskbay.review").review(a)
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
    -- Preview edge cases, driven through a stub preview.
    local function preview(item)
      local shown
      item.cwd = a.path
      require("taskbay.review").preview({ item = item, picker = { closed = false, current = function() return item end }, preview = {
        reset = function() end, set_title = function() end, highlight = function() end,
        set_lines = function(_, lines) shown = lines end, win = { valid = function() return true end },
      } })
      assert(vim.wait(5000, function() return shown ~= nil and shown[1] ~= "Loading diff..." end, 10))
      return shown
    end
    assert(preview({ file = "same name.txt", base = "no-such-ref" })[1] == "Diff failed:")
    vim.fn.writefile(vim.fn["repeat"]({ "x" }, 10001), a.path .. "/big.txt")
    assert(preview({ file = "big.txt", untracked = true })[1]:find("truncated to 10,000", 1, true))
    vim.fn.delete(a.path .. "/big.txt")
    assert(preview({ file = "absent.txt" })[1]:find("No textual diff", 1, true))
    -- Picker actions: refresh, scope switch, and confirm on deleted and present files.
    local function next_picker(title)
      local found
      assert(vim.wait(5000, function()
        found = Snacks.picker.get()[1]
        return found ~= nil and found.opts.title:find(title, 1, true) ~= nil
      end, 10), "Picker missing: " .. title)
      return found
    end
    require("taskbay.review").review(a)
    local p = next_picker("working changes")
    p.opts.actions.refresh_issue(p)
    p = next_picker("working changes")
    local count = #messages
    p.opts.confirm(p, { file = "gone.txt", status = "D" })
    assert(messages[count + 1]:find("Deleted file", 1, true) and not p.closed, "Deleted files stay in the picker")
    p.opts.confirm(p, { file = "review.txt" })
    assert(vim.api.nvim_buf_get_name(0) == a.path .. "/review.txt" and core.current() == a, "Confirm opens the file")
    require("taskbay.review").review(a)
    p = next_picker("working changes")
    p.opts.actions.issue_scope(p)
    assert(vim.wait(5000, function()
      local q = Snacks.picker.get()[1]
      return (q and q.opts.title:find("issue changes", 1, true)) or messages[#messages]:find("No issue changes", 1, true)
    end, 10), "The scope key switches to the recorded base")
    for _, q in ipairs(Snacks.picker.get()) do q:close() end
    require("taskbay.review").review(nil)
    p = next_picker("working changes")
    p.opts.actions.issue_scope(p)
    assert(messages[#messages]:find("requires a task workspace", 1, true))
    local files = core.files
    core.files = function() return {} end
    require("taskbay.review").review(a)
    assert(vim.wait(3000, function() return messages[#messages]:find("No working changes", 1, true) end, 10))
    core.files = files
  end
  ui.dashboard()
  local panel = vim.api.nvim_get_current_win()
  assert(vim.api.nvim_win_get_config(panel).relative == "editor", "Dashboard is a compact floating panel")
  assert(vim.wo.cursorline and vim.wo.signcolumn == "no")
  assert(#vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, {}) > 0, "Dashboard uses restrained semantic highlighting")
  vim.api.nvim_win_close(panel, true)
  assert(vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true }).str:find("repo#"))
  assert(vim.api.nvim_tabpage_is_valid(tab_b) and uv.fs_stat(a.path), "Closing the panel preserves tabs/worktrees")

  -- Finishing (local task): commit the worktree, merge into the main checkout, mark finished.
  local tasks = require("taskbay.store")
  local lrepo = { root = temp .. "/repo", common = temp .. "/repo/.git", source = "local", repo = "repo", host = "local" }
  local local_task = tasks.create(lrepo, "Finish me")
  local lws = await(function() return core.prepare(lrepo, local_task, "main", true) end)
  write(lws.path .. "/finished-work.txt", { "merged from the task worktree" })

  -- Finish while pi is still running: one prompt stops pi, commits and merges.
  await(function() core.start(lws) end)
  assert(vim.wait(5000, function() return core.jobs[lws.id] and core.jobs[lws.id].sequence ~= nil end, 10),
    "Stub pi did not report ready before finish")
  local real_finish_choose, ok_finish, err_finish = core.choose
  await(function()
    core.choose = function(items, prompt)
      ok_finish = prompt
      return "Stop the agent, commit and merge"
    end
    ok_finish, err_finish = pcall(core.finish, lws)
    core.choose = real_finish_choose
  end)
  assert(ok_finish, err_finish)
  assert(core.jobs[lws.id] and core.jobs[lws.id].exited, "Finishing must stop the running pi")
  assert(lws.finished and core.status(lws) == "finished", "Finishing must mark the task finished")
  assert(uv.fs_stat(lrepo.root .. "/finished-work.txt"), "Finish must merge the branch into the main checkout")

  -- Finishing again repeats the merge; nothing is lost, the state stays finished.
  await(function()
    core.choose = function() return "Commit and merge" end
    ok_finish, err_finish = pcall(core.finish, lws)
    core.choose = real_finish_choose
  end)
  assert(ok_finish, err_finish)
  assert(lws.finished and core.status(lws) == "finished", "A repeated finish stays finished")

  -- Restarting clears the finished state and replays the task; deleting removes everything.
  await(function() core.restart(lws) end)
  assert(vim.wait(8000, function() return lws.finished == nil end, 10), "Restarting clears the finished state")
  assert(vim.wait(8000, function()
    local rjob = core.jobs[lws.id]
    return rjob and not rjob.exited and rjob.sequence ~= nil
  end, 10), "A restart relaunches pi")
  assert(vim.tbl_contains(core.jobs[lws.id].argv, "Implement the attached task."),
    "A restart replays the task text in a fresh conversation")
  await(function() core.delete(lws) end)
  assert(vim.wait(8000, function()
    return not core.jobs[lws.id] and not core.workspaces[lws.id]
      and not uv.fs_stat(lws.path)
      and vim.fn.glob(lrepo.root .. "/.tasks/" .. local_task.number .. "-*") == ""
  end, 10), "Deleting stops pi and removes worktree, task file and sidecar")
  assert(cmd({ "git", "branch", "--list", lws.branch }, lrepo.root) == "", "Deleting removes the task branch")

  -- Deleting while pi runs: deletion stops pi itself, then removes everything.
  local delete_task = tasks.create(lrepo, "Delete me running")
  local lws2 = await(function() return core.prepare(lrepo, delete_task, "main", true) end)
  await(function() core.start(lws2) end)
  assert(vim.wait(5000, function() return core.jobs[lws2.id] and core.jobs[lws2.id].sequence ~= nil end, 10),
    "Stub pi did not report ready before delete")
  await(function() core.delete(lws2) end)
  assert(not core.jobs[lws2.id], "Deleting must remove the job entry")
  assert(not uv.fs_stat(lws2.path), "Deleting must remove the worktree")
  assert(vim.fn.glob(lrepo.root .. "/.tasks/" .. delete_task.number .. "-*") == ""
    and vim.fn.glob(lrepo.root .. "/.tasks/" .. delete_task.number .. ".json") == "",
    "Deleting must remove the task file and sidecar")
  expect_error(function() tasks.meta_path(delete_task) end, "does not match")

  -- Workspace states without a live job: missing / external / prepared / finished.
  local ghost = { id = "ghost-status", path = temp .. "/never-created", number = 1, title = "Ghost",
    source = "local", task_root = lrepo.root, repo = "repo", host = "local", branch = "task/1", base_ref = "HEAD" }
  assert(core.status(ghost) == "missing", "A removed worktree reports itself missing")
  ghost.path = lrepo.root
  assert(core.status(ghost) == "prepared", "A workspace without a run is prepared")
  vim.uv.fs_mkdir(core.directory(ghost), 448)
  core.write(core.directory(ghost) .. "/owner.json", vim.json.encode({ pid = vim.fn.getpid(), token = "other" }))
  assert(core.status(ghost) == "external", "An owned state directory without a job is an external editor")
  vim.uv.fs_unlink(core.directory(ghost) .. "/owner.json")
  vim.fn.delete(core.directory(ghost), "rf")
  ghost.finished = os.time()
  assert(core.status(ghost) == "finished")
  ghost.finished = nil
  core.workspaces[ghost.id] = ghost -- register so tab routing finds it

  -- continue: refuse when not started, refuse while busy, paste when idle.
  expect_error(function() core.continue(b) end, "with p before continuing")
  await(function() core.start(a) end) -- resume; the stub settles idle
  assert(vim.wait(5000, function() return core.jobs[a.id].sequence ~= nil end, 10))
  local ajob = core.jobs[a.id]
  assert(core.status(a) == "idle" or core.status(a) == "no changes", core.status(a))
  ajob.activity = "working"
  expect_error(function() core.continue(a) end, "continue once it is idle")
  -- An idle turn that changed nothing must get the explicit implement-now message.
  ajob.activity, ajob.worked, ajob.settled_at, a.files, a.refreshed_at = "idle", true, uv.now() - 1000, 0, uv.now()
  assert(core.status(a) == "no changes", "A settled turn with zero worktree changes reports 'no changes'")
  core.continue(a)
  assert(vim.wait(3000, function()
    local text = uv.fs_stat(core.directory(a) .. "/paste.txt")
      and table.concat(vim.fn.readfile(core.directory(a) .. "/paste.txt"), "\n") or ""
    return text:find("left the worktree unchanged", 1, true) ~= nil
  end, 10), "A 'no changes' task is asked to implement now")
  core.stop(a)
  assert(vim.wait(4000, function() return core.jobs[a.id].exited end, 10))

  -- Diff scope values are a closed set.
  expect_error(function() core.files(a, "bogus") end, "Unknown diff scope")

  -- Status/tabline rendering must survive live and absent workspaces alike.
  core.open(b)
  local sl = ui.statusline()
  assert(sl:find("Pi ", 1, true) and sl:find(tasks.label(b), 1, true),
    "The statusline shows the task label and status: " .. vim.inspect(sl))
  core.open(ghost)
  local ghost_sl = ui.statusline()
  assert(ghost_sl:find("prepared", 1, true), "A prepared workspace renders its status: " .. vim.inspect(ghost_sl))
  assert(ui.tabline():find("Tab 1", 1, true), "Tabs that are not task tabs render as plain tabs")
  vim.cmd("tabclose")
  core.workspaces[ghost.id] = nil

  -- Launching from a repository without any commit explains the worktree prerequisite.
  vim.fn.mkdir(temp .. "/bare", "p")
  git("init", "-b", "main", temp .. "/bare")
  local bare = { root = temp .. "/bare", common = temp .. "/bare/.git", source = "local", repo = "bare", host = "local" }
  local launch_msg = #messages
  ui.launch(bare, { number = 1, title = "No commits" })
  assert(vim.wait(5000, function() return #messages > launch_msg and tostring(messages[#messages]):find("no commits yet", 1, true)
    end, 10), "An unborn repository gets the commit-first explanation: " .. table.concat(messages, "\n"))
  vim.fn.delete(temp .. "/bare", "rf")

  -- Toggling the GitHub integration flips the setting and tells the user.
  local before = core.settings().remote_enabled
  ui.toggle_remote()
  assert(core.settings().remote_enabled == not before)
  assert(tostring(messages[#messages]):find(before and "disabled" or "enabled", 1, true))
  ui.toggle_remote()
  assert(core.settings().remote_enabled == before)

  -- Dependency installation guards on npm instead of running mid-suite.
  local exec = vim.fn.executable
  vim.fn.executable = function(name) return name == "npm" and 0 or exec(name) end
  ui.install()
  vim.fn.executable = exec
  assert(tostring(messages[#messages]):find("npm is required", 1, true), "install explains a missing npm")

  -- Core error paths.
  local function last(pattern)
    return vim.wait(3000, function() return tostring(messages[#messages]):find(pattern, 1, true) ~= nil end, 10)
  end
  local function fails(fn, pattern) expect_error(function() await(fn) end, pattern) end
  fails(function() core.run({ "false" }) end, "false failed (1)")
  local bad = core.settings().state_dir .. "/" .. ("f"):rep(24)
  vim.fn.mkdir(bad, "p")
  write(bad .. "/workspace.json", { "{}" })
  dofile(vim.api.nvim_get_runtime_file("lua/taskbay/core.lua", false)[1]).load()
  assert(last("Cannot restore workspace metadata"), "Invalid saved metadata is reported, not loaded")
  vim.fn.delete(bad, "rf")

  -- A branch checked out elsewhere is reused only on request and never while locked.
  local elsewhere = temp .. "/elsewhere-77"
  git("worktree", "add", "-b", tasks.branch({ source = repo.source, host = repo.host, repo = repo.repo, number = 77 }),
    elsewhere, "HEAD")
  fails(function() core.prepare(repo, { number = 77, title = "Elsewhere" }, "main") end, "already checked out")
  git("worktree", "lock", elsewhere)
  fails(function() core.prepare(repo, { number = 77, title = "Elsewhere" }, "main", true) end, "Worktree is locked")
  git("worktree", "unlock", elsewhere)
  assert(await(function() return core.prepare(repo, { number = 77, title = "Elsewhere" }, "main", true) end).path
    == core.real(elsewhere), "Reuse adopts the existing worktree")

  -- A branch without a worktree is reused only on request.
  git("branch", tasks.branch({ source = repo.source, host = repo.host, repo = repo.repo, number = 78 }))
  fails(function() core.prepare(repo, { number = 78, title = "Branch only" }, "main") end, "Branch already exists")
  assert(uv.fs_stat(await(function() return core.prepare(repo, { number = 78, title = "Branch only" }, "main", true) end).path))

  -- An abandoned lock (editor and agent both gone) is recovered after confirmation.
  local dead = vim.fn.jobstart({ "true" })
  local dead_pid = vim.fn.jobpid(dead)
  vim.fn.jobwait({ dead })
  core.write(core.directory(a) .. "/owner.json", vim.json.encode({ pid = dead_pid, token = "gone" }))
  local choose = core.choose
  core.choose = function() return "Recover abandoned lock" end
  core.lock(a, "recovered")
  core.unlock(a)
  core.choose = choose

  -- A started task without a saved session never silently starts a new conversation.
  local session_file = a.session_file
  a.session_file = nil
  fails(function() core.start(a) end, "did not report a saved session")
  a.session_file = session_file
  -- Losing the last slot while recovering ownership keeps the workspace for later.
  local lock, live = core.lock, core.live
  core.lock = function(...)
    lock(...)
    core.live = function() return core.settings().max_agents end
  end
  fails(function() core.start(a) end, "during ownership recovery")
  core.lock, core.live = lock, live
  -- A watcher that cannot start fails the launch and releases the lock.
  local new_fs_event = vim.uv.new_fs_event
  vim.uv.new_fs_event = function()
    return { start = function() return nil, "boom" end, stop = function() end, close = function() end,
      is_closing = function() return false end }
  end
  fails(function() core.start(a) end, "Cannot watch the agent lifecycle: boom")
  -- Watcher errors, unreadable status files and a silent pi are reported.
  local on_event, on_timeout
  vim.uv.new_fs_event = function()
    local watcher = new_fs_event()
    return setmetatable({ start = function(_, path, flags, callback)
      on_event = callback
      return watcher:start(path, flags, callback)
    end }, { __index = function(_, key) return function(_, ...) return watcher[key](watcher, ...) end end })
  end
  local defer_fn = vim.defer_fn
  vim.defer_fn = function(fn, ms)
    if ms == 5000 then on_timeout = fn else return defer_fn(fn, ms) end
  end
  await(function() core.start(a) end)
  vim.uv.new_fs_event, vim.defer_fn = new_fs_event, defer_fn
  local job = core.jobs[a.id]
  on_event("boom")
  assert(last("Agent status watcher: boom"))
  write(core.directory(a) .. "/" .. job.run .. ".json", { "{" })
  on_event(nil, job.run .. ".json")
  assert(last("Cannot read agent status"))
  job.sequence = nil
  on_timeout()
  assert(job.activity == "unknown" and last("lifecycle reporting is unavailable"))
  -- Cancelling a restart keeps the running conversation.
  core.choose = function() return "Cancel" end
  await(function() core.restart(a) end)
  assert(core.jobs[a.id] == job and not job.exited, "A cancelled restart changes nothing")
  core.choose = choose
  -- Quitting stops live agents and closes their watchers.
  vim.api.nvim_exec_autocmds("VimLeavePre", { group = "taskbay" })
  assert(vim.wait(4000, function() return job.exited end, 10) and job.watcher:is_closing(), "Quit stops pi and its watcher")

  -- Finish reports merge conflicts; delete refuses unsaved task edits.
  local conflict = tasks.create(lrepo, "Conflicting work")
  local cws = await(function() return core.prepare(lrepo, { number = conflict.number, title = conflict.title }, "main") end)
  write(cws.path .. "/conflict.txt", { "worktree" })
  write(lrepo.root .. "/conflict.txt", { "main" })
  cmd({ "git", "add", "conflict.txt" }, lrepo.root)
  cmd({ "git", "commit", "-m", "Conflict" }, lrepo.root)
  core.choose = function() return "Commit and merge" end
  fails(function() core.finish(cws) end, "Merge failed")
  cmd({ "git", "merge", "--abort" }, lrepo.root)
  vim.cmd.edit(vim.fn.fnameescape(tasks.file(cws)))
  vim.api.nvim_buf_set_lines(0, -1, -1, false, { "unsaved" })
  fails(function() core.delete(cws) end, "Save or discard modified task buffers")
  vim.bo.modified = false
  core.choose = choose

  -- Refresh reports Git failures once and clears the file count.
  vim.fn.mkdir(temp .. "/not-git", "p")
  local broken = vim.tbl_extend("force", a, { id = "broken", path = temp .. "/not-git" })
  await(function() core.refresh(broken) end)
  assert(broken.files == nil and broken.git_error and last("Cannot refresh"))
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
print("taskbay core: routing, Git scopes, lifecycle, context, stop/resume and dashboard passed")
vim.cmd("qa!")
