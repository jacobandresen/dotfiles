local M = { workspaces = {}, jobs = {} }
local tasks = require("util.pi_tasks")
local uv = vim.uv
local token = vim.fn.sha256(tostring(uv.hrtime()) .. ":" .. vim.fn.getpid()):sub(1, 24)
local initialized = false
local loaded = false

local function notify(message, level) vim.notify(message, level or vim.log.levels.ERROR, { title = "Pi Tasks" }) end

function M.settings()
  local settings = vim.tbl_extend("force", {
    max_agents = 3,
    github_enabled = false,
    state_dir = vim.fn.stdpath("state") .. "/pi-issues",
    pi = "pi",
  }, vim.g.pi_issues or {})
  assert(
    type(settings.max_agents) == "number" and settings.max_agents >= 1 and settings.max_agents % 1 == 0,
    "pi_issues.max_agents must be a positive integer"
  )
  assert(type(settings.github_enabled) == "boolean", "pi_issues.github_enabled must be a boolean")
  return settings
end

function M.path() return vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h") .. "/pi" end

function M.clean(text) return (tostring(text or ""):gsub("[%z\1-\31\127]", " ")) end

function M.task(fn)
  local thread = coroutine.create(fn)
  local function resume(...)
    local ok, err = coroutine.resume(thread, ...)
    if not ok then notify(tostring(err)) end
  end
  resume()
  return thread
end

function M.run(argv, cwd, optional, stdin)
  local thread = coroutine.running()
  assert(thread, "Pi commands must run inside task()")
  local process = vim.system(argv, { cwd = cwd, timeout = 30000, stdin = stdin }, function(result)
    vim.schedule(function()
      local ok, err = coroutine.resume(thread, result)
      if not ok then notify(tostring(err)) end
    end)
  end)
  local result = coroutine.yield()
  if result.code ~= 0 and not optional then
    error(("%s failed (%d): %s"):format(argv[1], result.code, vim.trim(result.stderr or result.stdout or "")), 0)
  end
  return result, process
end

function M.choose(items, prompt)
  local thread = coroutine.running()
  vim.ui.select(items, { prompt = prompt }, function(choice)
    vim.schedule(function()
      local ok, err = coroutine.resume(thread, choice)
      if not ok then notify(tostring(err)) end
    end)
  end)
  return coroutine.yield()
end

function M.input(prompt, default)
  local thread = coroutine.running()
  vim.ui.input({ prompt = prompt, default = default }, function(value)
    vim.schedule(function()
      local ok, err = coroutine.resume(thread, value)
      if not ok then notify(tostring(err)) end
    end)
  end)
  return coroutine.yield()
end

local function git(root, ...)
  local result = M.run(vim.list_extend({ "git", "--no-pager" }, { ... }), root)
  return result.stdout
end
M.git = git

function M.real(path)
  local canonical, err = uv.fs_realpath(path)
  if canonical then return canonical end
  assert(not uv.fs_lstat(path), "Cannot resolve path " .. path .. ": " .. tostring(err))
  local parent = vim.fs.dirname(path)
  assert(parent and parent ~= path, "Cannot resolve path: " .. path)
  return vim.fs.joinpath(M.real(parent), vim.fs.basename(path))
end

function M.inside(path, root)
  path, root = M.real(path), M.real(root)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

function M.current() return M.workspaces[vim.t.pi_issue or ""] end

function M.root()
  local workspace = M.current()
  return workspace and workspace.path or LazyVim.root()
end

local function directory(workspace) return M.settings().state_dir .. "/" .. workspace.id end
M.directory = directory

function M.write(path, data)
  vim.fn.mkdir(vim.fs.dirname(path), "p", 448)
  local temporary = path .. "." .. token .. ".tmp"
  local fd, err = uv.fs_open(temporary, "w", 384)
  assert(fd, err)
  local ok, write_err = uv.fs_write(fd, data, 0)
  uv.fs_close(fd)
  assert(ok, write_err)
  local renamed, rename_err = uv.fs_rename(temporary, path)
  assert(renamed, rename_err)
end

local fields = {
  "id",
  "common",
  "repo",
  "host",
  "number",
  "title",
  "url",
  "path",
  "branch",
  "base_ref",
  "base_sha",
  "session",
  "session_file",
  "started",
  "source",
  "task_root",
  "task_file",
}
function M.save(workspace)
  local data = { version = 1 }
  for _, field in ipairs(fields) do
    data[field] = workspace[field]
  end
  M.write(directory(workspace) .. "/workspace.json", vim.json.encode(data))
end

function M.load()
  if loaded then return end
  loaded = true
  local root = M.settings().state_dir
  if not uv.fs_stat(root) then return end
  for name, kind in vim.fs.dir(root) do
    if kind == "directory" and name:match("^[a-f0-9]+$") then
      local path = root .. "/" .. name .. "/workspace.json"
      if uv.fs_stat(path) then
        local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(path), "\n")) end)
        if
          ok
          and type(data) == "table"
          and data.version == 1
          and data.id == name
          and type(data.path) == "string"
          and type(data.common) == "string"
          and type(data.repo) == "string"
          and type(data.host) == "string"
          and type(data.title) == "string"
          and type(data.branch) == "string"
          and type(data.base_ref) == "string"
          and type(data.base_sha) == "string"
          and type(data.session) == "string"
          and type(data.number) == "number"
          and data.number > 0
          and data.number <= 9007199254740991
          and data.number % 1 == 0
          and (data.source == nil or data.source == "github"
            or (data.source == "local" and type(data.task_root) == "string" and type(data.task_file) == "string"))
        then
          M.workspaces[name] = data
        else
          notify("Cannot restore workspace metadata: " .. path)
        end
      end
    end
  end
end

function M.worktrees(root)
  local entries, current = {}, nil
  for _, field in ipairs(vim.split(git(root, "worktree", "list", "--porcelain", "-z"), "\0", { plain = true })) do
    if field:sub(1, 9) == "worktree " then
      current = { path = M.real(field:sub(10)) }
      entries[#entries + 1] = current
    elseif current and field:sub(1, 7) == "branch " then
      current.branch = field:sub(8):gsub("^refs/heads/", "")
    elseif current and field:match("^locked") then
      current.locked = true
    end
  end
  return entries
end

function M.repository(root, source)
  return tasks.repository(root, source or "local")
end

function M.base(repo, ref)
  local result = M.run({ "git", "rev-parse", "--verify", "--end-of-options", ref .. "^{commit}" }, repo.root, true)
  if result.code ~= 0 then return nil end
  return vim.trim(result.stdout)
end

-- True when the current branch has no commits yet (a fresh git init).
function M.unborn(repo)
  return M.run({ "git", "rev-parse", "--verify", "--quiet", "HEAD" }, repo.root, true).code ~= 0
    and M.run({ "git", "symbolic-ref", "--quiet", "HEAD" }, repo.root, true).code == 0
end

function M.prepare(repo, issue, ref, reuse, base_sha)
  M.load()
  assert(repo.source == "local" or M.settings().github_enabled,
    "GitHub integration is disabled; set vim.g.pi_issues.github_enabled = true to enable it")
  assert(type(issue.number) == "number" and issue.number > 0 and issue.number <= 9007199254740991
    and issue.number % 1 == 0, "Invalid issue number")
  local target = {
    source = repo.source, host = repo.host, repo = repo.repo, number = issue.number,
    task_root = repo.task_root or (repo.source == "local" and repo.root or nil),
    task_file = issue.task_file,
  }
  if repo.source == "local" then
    local current = tasks.get(target)
    target.task_file = current.task_file
    issue = vim.tbl_extend("force", issue, current)
  end
  local key = repo.source == "local" and tasks.identity(target)
    or (repo.host .. "/" .. repo.repo .. "\0" .. issue.number)
  local id = vim.fn.sha256(repo.common .. "\0" .. key):sub(1, 24)
  if M.workspaces[id] then
    M.validate(M.workspaces[id])
    return M.workspaces[id]
  end
  local sha = base_sha or assert(M.base(repo, ref), "Base ref does not resolve to a commit: " .. ref)
  local branch = tasks.branch(target)
  local path = tasks.worktree(repo, issue.number)
  for _, existing in pairs(M.workspaces) do
    assert(
      existing.common ~= repo.common or (existing.branch ~= branch and existing.path ~= path),
      "This branch/path belongs to a different issue repository; use a separate checkout"
    )
  end
  local attached
  for _, entry in ipairs(M.worktrees(repo.root)) do
    if entry.branch == branch then attached = entry end
  end
  if attached then
    assert(reuse, "Branch is already checked out at " .. attached.path)
    assert(not attached.locked, "Worktree is locked: " .. attached.path)
    path = attached.path
  else
    assert(not uv.fs_lstat(path), "Path already exists and is not the selected worktree: " .. path)
    local exists = M.run({ "git", "show-ref", "--verify", "--quiet", "refs/heads/" .. branch }, repo.root, true)
    if exists.code == 0 then
      assert(reuse, "Branch already exists: " .. branch)
      git(repo.root, "worktree", "add", path, branch)
    else
      git(repo.root, "worktree", "add", "-b", branch, path, sha)
    end
  end
  local workspace = {
    id = id,
    common = repo.common,
    repo = repo.repo,
    host = repo.host,
    number = issue.number,
    title = M.clean(issue.title),
    url = issue.url,
    source = repo.source,
    task_root = target.task_root,
    task_file = target.task_file,
    path = M.real(path),
    branch = branch,
    base_ref = ref,
    base_sha = sha,
    session = (repo.source == "local" and "task-" or "issue-") .. id,
  }
  M.save(workspace)
  M.workspaces[id] = workspace
  return workspace
end

function M.validate(workspace)
  assert(uv.fs_stat(workspace.path), "Worktree is missing: " .. workspace.path)
  local common = M.real(vim.trim(git(workspace.path, "rev-parse", "--path-format=absolute", "--git-common-dir")))
  assert(common == workspace.common, "Worktree now belongs to another repository")
  local branch = vim.trim(git(workspace.path, "branch", "--show-current"))
  assert(branch == workspace.branch, "Worktree branch changed; expected " .. workspace.branch .. ", found " .. branch)
  local found = false
  for _, entry in ipairs(M.worktrees(workspace.path)) do
    if entry.path == workspace.path then
      assert(not entry.locked, "Worktree is locked: " .. workspace.path)
      found = true
    end
  end
  assert(found, "Path is no longer a registered worktree")
end

function M.open(workspace)
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if vim.t[tab].pi_issue == workspace.id then
      vim.api.nvim_set_current_tabpage(tab)
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if
          vim.api.nvim_win_get_config(win).relative == ""
          and vim.bo[vim.api.nvim_win_get_buf(win)].buftype ~= "terminal"
        then
          vim.api.nvim_set_current_win(win)
          break
        end
      end
      return
    end
  end
  assert(uv.fs_stat(workspace.path), "Worktree is missing: " .. workspace.path)
  vim.cmd.tabnew()
  vim.t.pi_issue = workspace.id
  require("util.pi_issues_ui").tabs()
  vim.api.nvim_cmd({ cmd = "tcd", args = { workspace.path } }, {})
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "# " .. tasks.label(workspace) .. ": " .. workspace.title,
    "",
    workspace.url or "",
    "",
    "Space a p   Pi agent (configured default model)",
    "F6          Hide / show Pi, also from terminal input",
    "Space a s   Send file / selection",
    "Space a r   Reviewer subagent",
    "Space g D   Review changes",
    "Space f f   Find files in this worktree",
    "Space a v   View / edit task",
    "Space a e   Ask pi to revise task",
    "Space a w   All task workspaces",
    "",
    "Worktree: " .. workspace.path,
    "Branch: " .. workspace.branch,
    "Base: " .. workspace.base_ref,
    "",
    "Agents do not commit, merge, publish, or remove worktrees automatically.",
  })
  vim.bo[buf].modifiable = false
end

local function alive(pid)
  if type(pid) ~= "number" or pid <= 0 then return false end
  local result, err = uv.kill(pid, 0)
  return result ~= nil or not tostring(err):find("ESRCH", 1, true)
end

function M.lock(workspace, run)
  local path = directory(workspace) .. "/owner.json"
  vim.fn.mkdir(directory(workspace), "p", 448)
  local fd = uv.fs_open(path, "wx", 384)
  if not fd then
    local ok, owner = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(path), "\n")) end)
    if
      ok
      and type(owner) == "table"
      and type(owner.pid) == "number"
      and not alive(owner.pid)
      and (not owner.job_pid or not alive(owner.job_pid))
    then
      assert(
        M.choose(
          { "Cancel", "Recover abandoned lock" },
          "Both the recorded editor and agent have exited. Recover " .. tasks.label(workspace) .. "?"
        ) == "Recover abandoned lock",
        "Ownership recovery cancelled"
      )
      local recovery_path = path .. ".recovery"
      local guard =
        assert(uv.fs_open(recovery_path, "wx", 384), "Another editor is recovering this workspace: " .. recovery_path)
      local recovered, recovered_fd = pcall(function()
        local current = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
        assert(
          type(current.pid) == "number"
            and not alive(current.pid)
            and (not current.job_pid or not alive(current.job_pid)),
          "Workspace owner changed during recovery; inspect before retrying"
        )
        assert(uv.fs_unlink(path))
        return uv.fs_open(path, "wx", 384)
      end)
      uv.fs_close(guard)
      assert(uv.fs_unlink(recovery_path))
      assert(recovered, recovered_fd)
      fd = recovered_fd
    end
  end
  assert(fd, "Workspace is owned by another editor (or has an unknown owner): " .. path)
  local written, err = uv.fs_write(fd, vim.json.encode({ token = token, run = run, pid = vim.fn.getpid() }), 0)
  uv.fs_close(fd)
  assert(written, err)
end

function M.unlock(workspace)
  local path = directory(workspace) .. "/owner.json"
  if not uv.fs_stat(path) then return end
  local ok, owner = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(path), "\n")) end)
  if ok and owner.token == token then assert(uv.fs_unlink(path)) end
end

function M.changed()
  vim.api.nvim_exec_autocmds("User", { pattern = "PiIssuesChanged", modeline = false })
  vim.cmd.redrawstatus()
end

function M.accept_status(workspace, job, data)
  if
    M.jobs[workspace.id] ~= job
    or job.exited
    or type(data) ~= "table"
    or data.version ~= 1
    or data.run ~= job.run
    or type(data.sequence) ~= "number"
    or data.sequence <= (job.sequence or 0)
  then
    return false
  end
  if not vim.tbl_contains({ "idle", "working", "waiting", "exited" }, data.activity) then return false end
  if data.cwd ~= workspace.path or type(data.session) ~= "string" then return false end
  local settled = job.activity ~= "idle" and data.activity == "idle"
  job.sequence, job.activity, job.outcome = data.sequence, data.activity, data.outcome
  -- Snapshots can coalesce; a settle outcome also proves a turn ran.
  if data.activity == "working" or (data.outcome and data.outcome ~= "unknown") then job.worked = true end
  if settled then job.settled_at = uv.hrtime() end
  job.model = M.clean(data.model)
  workspace.session = data.session
  workspace.session_file = type(data.session_file) == "string" and data.session_file or nil
  M.save(workspace)
  M.changed()
  if settled then M.task(function() M.refresh(workspace) end) end
  return true
end

function M.show(workspace)
  local job = M.jobs[workspace.id]
  if not job or not vim.api.nvim_buf_is_valid(job.buf) then return end
  M.open(workspace)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == job.buf then
      vim.api.nvim_set_current_win(win)
      if not job.exited then vim.cmd.startinsert() end
      return
    end
  end
  vim.cmd("botright vsplit")
  vim.api.nvim_win_set_buf(0, job.buf)
  vim.api.nvim_win_set_width(0, math.max(30, math.floor(vim.o.columns * 0.4)))
  vim.wo.number, vim.wo.relativenumber, vim.wo.signcolumn = false, false, "no"
  vim.wo.winbar = " Pi " .. workspace.number .. " "
  if not job.exited then vim.cmd.startinsert() end
end

function M.start(workspace, issue)
  M.validate(workspace)
  local previous = M.jobs[workspace.id]
  if previous and not previous.exited then return M.show(workspace) end
  local count = 0
  for _, job in pairs(M.jobs) do
    if not job.exited then count = count + 1 end
  end
  assert(count < M.settings().max_agents, "Agent limit reached; stop an issue from Space a w before starting another")
  assert(vim.fn.executable(M.settings().pi) == 1, "pi is not installed")
  assert(
    uv.fs_stat(M.path() .. "/node_modules/pi-subagents/bundle/index.js"),
    "Run :PiIssuesSetup to install the pinned pi extension"
  )
  if workspace.session_file then
    assert(
      uv.fs_stat(workspace.session_file),
      "Saved pi session is missing; inspect the workspace before starting a new conversation"
    )
    local header = vim.json.decode(vim.fn.readfile(workspace.session_file, "", 1)[1] or "")
    assert(
      header.type == "session"
        and type(header.cwd) == "string"
        and M.real(header.cwd) == workspace.path
        and header.id == workspace.session,
      "Saved pi session identity or working directory does not match"
    )
  elseif workspace.started then
    error(
      "The previous pi run did not report a saved session. Inspect its terminal; no new conversation was started.",
      0
    )
  end
  if not workspace.started and (not issue or issue.body == nil) then
    issue = tasks.get(workspace)
  end
  local run = vim.fn.sha256(token .. tostring(uv.hrtime())):sub(1, 24)
  local argv = {
    M.settings().pi,
    "--theme",
    vim.fs.dirname(M.path()) .. "/themes/pi-retrobox.json",
    "--use-theme",
    "retrobox",
    "--extension",
    M.path() .. "/extension.ts",
  }
  if M.settings().provider then vim.list_extend(argv, { "--provider", M.settings().provider }) end
  if M.settings().model then vim.list_extend(argv, { "--model", M.settings().model }) end
  if workspace.session_file then
    vim.list_extend(argv, { "--session", workspace.session_file })
  else
    vim.list_extend(argv, { "--session-id", workspace.session, "--name", tasks.label(workspace) })
  end
  if not workspace.started then
    local body = issue and issue.body or ""
    assert(#body <= 100000, "Task body is too large; provide bounded task context manually")
    local prompt = "# "
      .. tasks.label(workspace)
      .. ": "
      .. workspace.title
      .. "\n\n"
      .. (workspace.url or "")
      .. "\n\n"
      .. body
      .. "\n\n"
      .. (workspace.source == "local" and ("Task description file (lives in the main checkout; do not edit it or "
        .. "anything else there): " .. tasks.file(workspace) .. "\n\n") or "")
      .. "Your worktree is " .. workspace.path .. " (branch " .. workspace.branch .. "). It is the repository "
      .. "root for this task: create and change files only inside it, and resolve relative paths from it. "
      .. "Implement only this task in this worktree. Follow repository instructions. "
      .. "Run relevant tests with a timeout and report actual results. Leave changes for human review; "
      .. "do not commit, merge, push, close issues, install dependencies, or remove worktrees without asking. "
      .. "If explicitly asked to delegate, use pi-subagents in the foreground with async: false, "
      .. "the current cwd, an explicit provider/model ID matching your active session model, "
      .. "and no managed worktree. Do not start background or external agents.\n"
    local task_file = directory(workspace) .. "/" .. run .. "-task.md"
    M.write(task_file, prompt)
    vim.list_extend(argv, { "--", "@" .. task_file, "Implement the attached task." })
  end
  previous = M.jobs[workspace.id]
  if previous and not previous.exited then return M.show(workspace) end
  count = 0
  for _, current in pairs(M.jobs) do
    if not current.exited then count = count + 1 end
  end
  assert(count < M.settings().max_agents, "Agent limit reached while preparing; workspace kept for later")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  local job = { buf = buf, run = run, activity = "starting", argv = argv }
  M.lock(workspace, run)
  count = 0
  for _, current in pairs(M.jobs) do
    if not current.exited then count = count + 1 end
  end
  if count >= M.settings().max_agents then
    M.unlock(workspace)
    error("Agent limit reached during ownership recovery; workspace kept for later", 0)
  end
  M.jobs[workspace.id] = job
  local status_file = directory(workspace) .. "/" .. run .. ".json"
  job.watcher = uv.new_fs_event()
  local watching, watch_error = job.watcher:start(
    directory(workspace),
    {},
    vim.schedule_wrap(function(err, filename)
      if err then
        notify("Pi status watcher: " .. err)
        return
      end
      if filename ~= run .. ".json" or job.exited then return end
      local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(status_file), "\n")) end)
      if not ok then
        notify("Cannot read pi status: " .. status_file)
        return
      end
      M.accept_status(workspace, job, data)
    end)
  )
  if not watching then
    job.watcher:close()
    job.exited = true
    job.activity = "error"
    M.unlock(workspace)
    error("Cannot watch pi lifecycle: " .. tostring(watch_error), 0)
  end
  local started, start_error = pcall(vim.api.nvim_buf_call, buf, function()
    job.channel = vim.fn.jobstart(argv, {
      term = true,
      cwd = workspace.path,
      env = {
        NVIM_PI_STATUS = status_file,
        NVIM_PI_RUN = run,
      },
      on_exit = function(_, code)
        vim.schedule(function()
          job.exited, job.code, job.activity = true, code, (job.stop_requested or code == 0) and "stopped" or "error"
          if job.watcher and not job.watcher:is_closing() then
            job.watcher:stop()
            job.watcher:close()
          end
          if M.jobs[workspace.id] == job then
            M.unlock(workspace)
            M.changed()
          end
        end)
      end,
    })
  end)
  if not started or job.channel <= 0 then
    job.exited = true
    job.activity = "error"
    job.watcher:stop()
    job.watcher:close()
    M.unlock(workspace)
    error(start_error or "Could not start pi", 0)
  end
  local pid = vim.fn.jobpid(job.channel)
  M.write(
    directory(workspace) .. "/owner.json",
    vim.json.encode({ token = token, run = run, pid = vim.fn.getpid(), job_pid = pid })
  )
  workspace.started = true
  M.save(workspace)
  vim.defer_fn(function()
    if M.jobs[workspace.id] == job and not job.exited and not job.sequence then
      job.activity = "unknown"
      notify(
        "Pi lifecycle reporting is unavailable for "
          .. tasks.label(workspace)
          .. "; inspect its terminal"
      )
      M.changed()
    end
  end, 5000)
  M.show(workspace)
  M.changed()
end

function M.stop(workspace)
  local job = M.jobs[workspace.id]
  if not job or job.exited then return end
  job.activity = "stopping"
  job.stop_requested = true
  vim.fn.jobstop(job.channel)
  M.changed()
end

-- Ask a live, settled agent to keep going; Enter is sent after the paste so pi submits it.
function M.continue(workspace)
  local job = M.jobs[workspace.id]
  assert(job and not job.exited, "Start " .. tasks.label(workspace) .. "'s pi with p before continuing it")
  assert(job.activity == "idle", "Pi is " .. tostring(job.activity) .. "; continue once it is idle")
  local text = M.status(workspace) == "no changes"
      and "Your last turn left the worktree unchanged, so the task is not done. Implement it now in this "
        .. "worktree with your tools, then report what changed."
    or "Continue this task where you left off in this worktree, then report what changed."
  vim.api.nvim_chan_send(job.channel, "\27[200~" .. text .. "\27[201~")
  vim.defer_fn(function()
    if M.jobs[workspace.id] == job and not job.exited then vim.api.nvim_chan_send(job.channel, "\r") end
  end, 150)
  vim.notify("Asked " .. tasks.label(workspace) .. " to continue", vim.log.levels.INFO, { title = "Pi Tasks" })
end

function M.quit()
  M.task(function()
    local function check_buffers()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        assert(
          not (vim.bo[buf].modified and (vim.bo[buf].buftype == "" or vim.bo[buf].buftype == "acwrite")),
          "Save or discard modified files before :PiQuit. Agents are still running."
        )
      end
    end
    check_buffers()
    local active = {}
    for id, job in pairs(M.jobs) do
      if not job.exited then active[#active + 1] = id end
    end
    if #active > 0 then
      local choice = M.choose(
        { "Cancel", "Stop agents and quit" },
        ("Stop %d pi agent(s)? Worktrees and sessions are kept."):format(#active)
      )
      if choice ~= "Stop agents and quit" then return end
      check_buffers()
      for _, id in ipairs(active) do
        M.stop(M.workspaces[id])
      end
      assert(
        vim.wait(4000, function()
          for _, id in ipairs(active) do
            if not M.jobs[id].exited then return false end
          end
          return true
        end, 20),
        "Agents are still stopping; inspect Space a w before quitting"
      )
    end
    vim.cmd.qall()
  end)
end

function M.status(workspace)
  local job = M.jobs[workspace.id]
  if not job then
    if uv.fs_stat(directory(workspace) .. "/owner.json") then return "external" end
    return uv.fs_stat(workspace.path) and (workspace.started and "stopped" or "prepared") or "missing"
  end
  if job.activity == "idle" and job.outcome == "error" then return "error" end
  -- A finished turn that left the worktree clean (counted after it settled) did not do the task.
  if job.activity == "idle" and job.worked and workspace.files == 0
    and (workspace.refreshed_at or 0) > (job.settled_at or 0) then
    return "no changes"
  end
  return job.activity
end

function M.files(workspace, scope)
  local rows = {}
  local function diff(staged)
    local argv = { "git", "--no-pager", "diff", "--no-ext-diff", "--no-textconv", "--name-status", "-z", "-M" }
    if scope == "issue" then
      argv[#argv + 1] = workspace.base_sha
    elseif staged then
      argv[#argv + 1] = "--cached"
    end
    argv[#argv + 1] = "--"
    local result = M.run(argv, workspace.path)
    local fields = vim.split(result.stdout, "\0", { plain = true, trimempty = true })
    local i = 1
    while i <= #fields do
      local status, path, old = fields[i], fields[i + 1], nil
      i = i + 2
      if status:match("^[RC]") then
        old, path, i = path, fields[i], i + 1
      end
      assert(path, "Invalid git diff record")
      rows[#rows + 1] = {
        file = path,
        old = old,
        status = status,
        cwd = workspace.path,
        staged = staged,
        scope = scope,
        base = scope == "issue" and workspace.base_sha or nil,
        text = ("%s [%s] %s"):format(
          status,
          scope == "issue" and "issue" or (staged and "staged" or "unstaged"),
          M.clean(old and (old .. " -> " .. path) or path)
        ),
      }
    end
  end
  diff(false)
  if scope ~= "issue" then diff(true) end
  local untracked = git(workspace.path, "ls-files", "--others", "--exclude-standard", "-z")
  for _, path in ipairs(vim.split(untracked, "\0", { plain = true, trimempty = true })) do
    rows[#rows + 1] = { file = path, cwd = workspace.path, untracked = true, text = "? [untracked] " .. M.clean(path) }
  end
  return rows
end

function M.refresh(workspace)
  if not uv.fs_stat(workspace.path) then return end
  if workspace.source == "local" then
    local current = tasks.get(workspace)
    if workspace.title ~= M.clean(current.title) then
      workspace.title = M.clean(current.title)
      M.save(workspace)
      M.changed()
    end
  end
  -- A refresh requested while one runs (e.g. an agent settling) must not be dropped:
  -- the running one may have read the worktree before the agent's last write.
  if workspace.refreshing then
    workspace.refresh_again = true
    return
  end
  workspace.refreshing = true
  local result = M.run({ "git", "status", "--porcelain=v1", "-z", "--untracked-files=all" }, workspace.path, true)
  workspace.refreshing = false
  if workspace.refresh_again then
    workspace.refresh_again = false
    return M.refresh(workspace)
  end
  if result.code ~= 0 then
    local message = M.clean(result.stderr)
    if workspace.git_error ~= message then
      notify("Cannot refresh " .. tasks.label(workspace) .. ": " .. message)
    end
    workspace.files = nil
    workspace.git_error = message
    M.changed()
    return
  end
  local records = vim.split(result.stdout, "\0", { plain = true, trimempty = true })
  local count, i = 0, 1
  while i <= #records do
    count = count + 1
    i = i + (records[i]:sub(1, 2):find("[RC]") and 2 or 1)
  end
  workspace.files, workspace.git_error, workspace.refreshed_at = count, nil, uv.hrtime()
  M.changed()
end

function M.setup()
  if initialized then return end
  initialized = true
  local group = vim.api.nvim_create_augroup("pi_issues", { clear = true })
  if _G.LazyVim then
    LazyVim.root.detectors.pi_issue = function()
      local workspace = M.current()
      return workspace and { workspace.path } or {}
    end
    local spec = vim.g.root_spec or { "lsp", { ".git", "lua" }, "cwd" }
    table.insert(spec, 1, "pi_issue")
    vim.g.root_spec = spec
  end
  vim.api.nvim_create_autocmd("TabEnter", {
    group = group,
    callback = function()
      if _G.LazyVim then LazyVim.root.cache = {} end
      local workspace = M.current()
      if workspace then M.task(function() M.refresh(workspace) end) end
    end,
  })
  vim.api.nvim_create_autocmd({ "TermLeave", "FocusGained" }, {
    group = group,
    callback = function()
      local workspace = M.current()
      if workspace then M.task(function() M.refresh(workspace) end) end
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for id, job in pairs(M.jobs) do
        if not job.exited then vim.fn.jobstop(job.channel) end
        if job.watcher and not job.watcher:is_closing() then
          job.watcher:stop()
          job.watcher:close()
        end
        if job.exited then M.unlock(M.workspaces[id]) end
      end
    end,
  })
end

return M
