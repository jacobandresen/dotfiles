local M = {}
local core = require("util.pi_issues")
local tasks = require("util.pi_tasks")
local dashboard
local dashboard_rows = {}
local accents = vim.api.nvim_create_namespace("pi_issues_dashboard")

local function geometry(max_width, desired_height)
  local width = math.max(1, math.min(max_width, vim.o.columns - 6))
  local height = math.max(1, math.min(desired_height, vim.o.lines - 6))
  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
  }
end

local function resize_with_editor(win, max_width, desired_height, redraw)
  local resize = vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      vim.api.nvim_win_set_config(win, geometry(max_width, desired_height))
      if redraw then redraw() end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function() vim.api.nvim_del_autocmd(resize) end,
  })
end

local function show_help(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden, vim.bo[buf].filetype, vim.bo[buf].modifiable = "wipe", "markdown", false
  local win = vim.api.nvim_open_win(buf, true, vim.tbl_extend("force", geometry(72, #lines), {
    style = "minimal", border = "rounded", title = " Task Help ", title_pos = "center",
    footer = " q close ", footer_pos = "center",
  }))
  vim.wo[win].wrap, vim.wo[win].linebreak = true, true
  resize_with_editor(win, 72, #lines)
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function() vim.api.nvim_win_close(win, false) end, { buffer = buf, nowait = true })
  end
end

local function clip(text, width)
  text = core.clean(text)
  if vim.fn.strdisplaywidth(text) <= width then return text end
  local chars = vim.fn.strchars(text)
  while chars > 0 and vim.fn.strdisplaywidth(vim.fn.strcharpart(text, 0, chars)) > width - 3 do
    chars = chars - 1
  end
  return vim.fn.strcharpart(text, 0, chars) .. "..."
end

local function safe(text) return (core.clean(text):gsub("%%", "%%%%")) end

function M.tabline()
  local parts = {}
  for i, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local workspace = core.workspaces[vim.t[tab].pi_issue or ""]
    local label = workspace
        and (vim.fs.basename(workspace.repo) .. (workspace.source == "local" and "/task-" or "#")
          .. workspace.number .. " " .. core.status(workspace))
      or ("Tab " .. i)
    parts[#parts + 1] = ("%s%%%dT %s %%T"):format(
      tab == vim.api.nvim_get_current_tabpage() and "%#TabLineSel#" or "%#TabLine#",
      i,
      safe(label)
    )
  end
  return table.concat(parts) .. "%#TabLineFill#%="
end

function M.tabs()
  vim.o.showtabline = 2
  vim.o.tabline = "%!v:lua.require'util.pi_issues_ui'.tabline()"
end

function M.statusline()
  local workspace = core.current()
  if not workspace then return "" end
  local job = core.jobs[workspace.id]
  local model = job and job.model or "pending"
  return safe(("Pi %s | %s | %s"):format(tasks.label(workspace), core.status(workspace), model))
end

function M.layout()
  return {
    layout = {
      box = "horizontal",
      width = 0,
      height = 0.9,
      { win = "preview", title = "{preview}", border = true },
      {
        box = "vertical",
        width = vim.o.columns < 90 and 0.25 or 0.3,
        border = true,
        title = " Changed Files ",
        { win = "input", height = 1, border = "bottom" },
        { win = "list", border = "none" },
      },
    },
  }
end

function M.preview(ctx)
  local item = ctx.item
  ctx.preview:reset()
  ctx.preview:set_title(core.clean(item.file))
  ctx.preview:set_lines({ "Loading diff..." })
  core.task(function()
    local argv = { "git", "--literal-pathspecs", "--no-pager", "diff", "--no-color", "--no-ext-diff", "--no-textconv" }
    if item.untracked then
      vim.list_extend(argv, { "--no-index", "--", "/dev/null", item.file })
    else
      if item.staged then argv[#argv + 1] = "--cached" end
      if item.base then argv[#argv + 1] = item.base end
      argv[#argv + 1] = "--"
      if item.old then argv[#argv + 1] = item.old end
      argv[#argv + 1] = item.file
    end
    local result = core.run(argv, item.cwd, true)
    if ctx.picker.closed or ctx.picker:current() ~= item or not ctx.preview.win:valid() then return end
    if result.code ~= 0 and not (item.untracked and result.code == 1) then
      ctx.preview:set_lines({ "Diff failed:", core.clean(result.stderr) })
      return
    end
    local lines = vim.split(result.stdout, "\n", { plain = true })
    if #lines > 10000 then
      lines = vim.list_slice(lines, 1, 10000)
      table.insert(lines, 1, "Preview truncated to 10,000 lines; open the file to inspect all content.")
    end
    if result.stdout == "" then lines = { "No textual diff (the file may have changed since refresh)." } end
    ctx.preview:set_lines(lines)
    ctx.preview:highlight({ ft = "diff" })
  end)
end

function M.review(workspace, scope)
  local path = workspace and workspace.path or core.root()
  local selected_scope = scope or "working"
  core.task(function()
    if workspace then core.validate(workspace) end
    local rows = core.files(workspace or { path = path }, selected_scope)
    if #rows == 0 then
      vim.notify("No " .. selected_scope .. " changes", vim.log.levels.INFO, { title = "Pi Review" })
      return
    end
    Snacks.picker({
      title = (workspace and (tasks.label(workspace) .. " - ") or "")
        .. selected_scope
        .. " changes",
      cwd = path,
      items = rows,
      format = "text",
      preview = M.preview,
      layout = M.layout(),
      previewers = { diff = { style = "syntax" } },
      confirm = function(picker, item)
        if item and item.status and item.status:sub(1, 1) == "D" then
          vim.notify("Deleted file; inspect its diff in the preview", vim.log.levels.INFO)
          return
        end
        picker:close()
        if workspace then core.open(workspace) end
        if item then vim.api.nvim_cmd({ cmd = "edit", args = { path .. "/" .. item.file } }, {}) end
      end,
      actions = {
        issue_scope = function(picker)
          picker:close()
          if not workspace then return vim.notify("Base comparison requires a task workspace", vim.log.levels.WARN) end
          M.review(workspace, selected_scope == "working" and "issue" or "working")
        end,
        refresh_issue = function(picker)
          picker:close()
          M.review(workspace, selected_scope)
        end,
      },
      win = {
        input = {
          keys = {
            ["<C-g>"] = { "issue_scope", mode = { "i", "n" }, desc = "Working / Recorded Base Changes" },
            ["<C-r>"] = { "refresh_issue", mode = { "i", "n" }, desc = "Refresh Diff" },
          },
        },
      },
    })
  end)
end

-- Jump to a task: its pi terminal when pi is running, otherwise its code tab.
function M.focus(workspace)
  core.task(function()
    core.validate(workspace)
    local job = core.jobs[workspace.id]
    if job and not job.exited then core.show(workspace) else core.open(workspace) end
  end)
end

local function ordered()
  local items = vim.tbl_values(core.workspaces)
  table.sort(items, function(a, b) return a.repo == b.repo and a.number < b.number or a.repo < b.repo end)
  return items
end

local rank = { waiting = 1, working = 2, ["no changes"] = 3, idle = 3, starting = 3, unknown = 3, stopping = 4 }
function M.switch()
  core.load()
  local items = {}
  for _, workspace in ipairs(ordered()) do
    local status = core.status(workspace)
    items[#items + 1] = {
      workspace = workspace, status = status, rank = rank[status] or 9,
      text = ("%-22s %-11s %s"):format(tasks.label(workspace), status, core.clean(workspace.title)),
    }
  end
  if #items == 0 then return vim.notify("No task workspaces yet; start one with Space a i", vim.log.levels.INFO) end
  table.sort(items, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.workspace.number < b.workspace.number
  end)
  Snacks.picker({
    title = "Switch Task",
    items = items,
    format = "text",
    layout = { preset = "select", layout = { footer = "Enter pi / Ctrl-o code tab", footer_pos = "center" } },
    confirm = function(picker, item)
      picker:close()
      if item then M.focus(item.workspace) end
    end,
    actions = {
      code_tab = function(picker)
        local item = picker:current()
        picker:close()
        if item then core.task(function() core.validate(item.workspace) core.open(item.workspace) end) end
      end,
    },
    win = { input = { keys = { ["<C-o>"] = { "code_tab", mode = { "n", "i" } } } } },
  })
end

local function workspace_for(target)
  for _, workspace in pairs(core.workspaces) do
    if tasks.identity(workspace) == tasks.identity(target) then return workspace end
  end
end

-- Restart the task of the current task buffer or tab with its current description.
function M.restart_current()
  local info = vim.b.pi_issue_draft
  local target = info and info.target or core.current()
  if not target then return vim.notify("Open a task (Space a i, Space a n) first", vim.log.levels.WARN) end
  local workspace = workspace_for(target)
  if not workspace then return M.start_current() end
  core.task(function()
    if info and vim.bo.modified then vim.cmd("silent write") end
    core.restart(workspace)
  end)
end

-- Start (or focus) the task of the current task buffer or task tab.
function M.start_current()
  local info = vim.b.pi_issue_draft
  local target = info and info.target or core.current()
  if not target then return vim.notify("Open a task (Space a i, Space a n) first", vim.log.levels.WARN) end
  core.task(function()
    if target.source ~= "local" then
      local workspace = core.current()
      assert(workspace, "Start GitHub issues from :PiIssues")
      return M.focus(workspace)
    end
    if vim.bo.modified and info then vim.cmd("silent write") end
    local repo = core.repository(target.task_root, "local")
    local task = tasks.get(target)
    M.launch(repo, { { number = target.number, title = task.title, task_file = task.task_file } })
  end)
end

-- Local tasks of the current repository that have no workspace yet ("new" rows).
local pending = { items = {} }
local function entry_id(entry) return entry.pending and ("new:" .. entry.pending.number) or entry.id end
local function entries()
  local list, started = ordered(), {}
  for _, workspace in ipairs(list) do
    if workspace.source == "local" then started[tasks.identity(workspace)] = true end
  end
  for _, item in ipairs(pending.items) do
    if not started[tasks.identity(item)] then list[#list + 1] = { pending = item, repo = pending.repo } end
  end
  return list
end
-- Best effort: the panel must open even outside Git or with an unreadable .tasks directory.
local function load_pending()
  local ok, result = pcall(function()
    local repo = core.repository(core.root(), "local")
    if repo.source ~= "local" then return { items = {} } end
    local items = {}
    for _, item in ipairs(tasks.list(repo, nil, 200)) do
      item.repo, item.host = repo.repo, "local"
      items[#items + 1] = item
    end
    return { repo = repo, items = items }
  end)
  pending = ok and result or { items = {} }
end
local function start_pending(entry)
  local item = entry.pending
  M.launch(entry.repo, { { number = item.number, title = item.title, task_file = item.task_file } })
end

local function draw()
  if not dashboard or not vim.api.nvim_buf_is_valid(dashboard) then return end
  local current_id
  for _, win in ipairs(vim.fn.win_findbuf(dashboard)) do
    local row = vim.api.nvim_win_get_cursor(win)[1]
    current_id = dashboard_rows[row] and entry_id(dashboard_rows[row])
  end
  local items = entries()
  local workspaces_count = #ordered()
  local active, waiting = 0, 0
  for _, job in pairs(core.jobs) do
    if not job.exited then active = active + 1 end
    if job.activity == "waiting" then waiting = waiting + 1 end
  end
  local wins = vim.fn.win_findbuf(dashboard)
  local width = #wins > 0 and vim.api.nvim_win_get_width(wins[1]) or 100
  local repo_width = math.min(28, math.floor(width * 0.3))
  local title_width = math.max(8, width - repo_width - 26)
  local format = "%2s %-" .. repo_width .. "s  %-10s %5s  %s"
  local lines = {
    "  Task workspaces",
    ("  %d active / %d slots    %d waiting    %d workspaces    %d new"):format(
      active,
      core.settings().max_agents,
      waiting,
      workspaces_count,
      #items - workspaces_count
    ),
    "",
    "  Pi status is not task completion; \"no changes\" means its turn left the worktree clean.",
    string.format(format, "", "TASK", "AGENT", "FILES", "TITLE"),
  }
  dashboard_rows = {}
  local selected = 6
  for index, entry in ipairs(items) do
    local new = entry.pending
    lines[#lines + 1] = string.format(
      format,
      index <= 9 and tostring(index) or "",
      clip(tasks.label(new and { source = "local", repo = entry.repo.repo, number = new.number } or entry), repo_width),
      new and "new" or core.status(entry),
      new and "-" or (entry.refreshing and "..." or (entry.files and tostring(entry.files) or "?")),
      clip(new and new.title or entry.title, title_width)
    )
    dashboard_rows[#lines] = entry
    if entry_id(entry) == current_id then selected = #lines end
  end
  if #items == 0 then lines[#lines + 1] = "  No tasks yet. Press n to write one." end
  vim.bo[dashboard].modifiable = true
  vim.api.nvim_buf_set_lines(dashboard, 0, -1, false, lines)
  vim.bo[dashboard].modifiable = false
  vim.api.nvim_buf_clear_namespace(dashboard, accents, 0, -1)
  local function highlight(row, col, group, last)
    vim.api.nvim_buf_set_extmark(dashboard, accents, row, col, { end_col = last or #lines[row + 1], hl_group = group })
  end
  highlight(0, 0, "Title")
  highlight(1, 0, "Comment")
  highlight(3, 0, "Comment")
  highlight(4, 0, "Comment")
  for row, entry in pairs(dashboard_rows) do
    local status = entry.pending and "new" or core.status(entry)
    local group = (status == "error" or status == "missing") and "DiagnosticError"
      or (status == "waiting" or status == "no changes") and "DiagnosticWarn"
      or status == "working" and "DiagnosticInfo"
      or status == "new" and "DiagnosticHint"
      or "Comment"
    highlight(row - 1, repo_width + 5, group, repo_width + 15)
  end
  for _, win in ipairs(vim.fn.win_findbuf(dashboard)) do
    if vim.api.nvim_win_get_height(win) < #lines and vim.api.nvim_win_get_config(win).relative ~= "" then
      vim.api.nvim_win_set_config(win, geometry(112, #lines))
    end
    vim.api.nvim_win_set_cursor(win, { math.min(selected, #lines), 0 })
  end
end

function M.dashboard()
  core.load()
  if dashboard and vim.api.nvim_buf_is_valid(dashboard) and #vim.fn.win_findbuf(dashboard) > 0 then
    vim.api.nvim_set_current_win(vim.fn.win_findbuf(dashboard)[1])
    draw()
    return
  end
  dashboard = vim.api.nvim_create_buf(false, true)
  vim.bo[dashboard].bufhidden = "wipe"
  vim.bo[dashboard].filetype = "pi_issues"
  vim.api.nvim_buf_set_name(dashboard, "pi://issues/" .. dashboard)
  local height = math.max(10, vim.tbl_count(core.workspaces) + 7)
  local size = geometry(112, height)
  local win = vim.api.nvim_open_win(
    dashboard,
    true,
    vim.tbl_extend("force", size, {
      relative = "editor",
      style = "minimal",
      border = "rounded",
      title = " Task Workspaces ",
      title_pos = "center",
      footer = size.width >= 64 and " 1-9 jump  Enter code  p pi  c continue  v task  X delete  n new  ? help  q "
        or " X delete  n new  Enter code  p pi  ? help ",
      footer_pos = "center",
    })
  )
  resize_with_editor(win, 112, height, draw)
  vim.wo.number, vim.wo.relativenumber, vim.wo.wrap, vim.wo.cursorline = false, false, false, true
  vim.wo.winblend, vim.wo.signcolumn = 0, "no"
  local function selected() return dashboard_rows[vim.api.nvim_win_get_cursor(0)[1]] end
  local function not_started() vim.notify("Not started yet; press p (or Enter) to start it", vim.log.levels.INFO) end
  -- on_new: what the key does on a "new" row (default: explain that it has not started).
  local function action(fn, on_new)
    return function()
      local entry = selected()
      if not entry then return end
      if entry.pending and on_new == nil then return not_started() end
      vim.cmd.close()
      if entry.pending then on_new(entry) else fn(entry) end
    end
  end
  local function refresh()
    for _, workspace in pairs(core.workspaces) do
      core.task(function() core.refresh(workspace) end)
    end
    core.task(function()
      load_pending()
      draw()
    end)
    draw()
  end
  local function view_pending(entry)
    local item = entry.pending
    require("util.pi_issue_edit").open({
      source = "local", task_root = entry.repo.root, number = item.number, task_file = item.task_file,
      repo = entry.repo.repo, host = "local", path = entry.repo.root,
    })
  end
  local maps = {
    ["<CR>"] = action(function(w)
      core.task(function()
        core.validate(w)
        core.open(w)
      end)
    end, start_pending),
    p = action(function(w)
      core.task(function() core.start(w) end)
    end, start_pending),
    R = action(function(w)
      core.task(function() core.restart(w) end)
    end, start_pending),
    c = function()
      local entry = selected()
      if entry and entry.pending then return not_started() end
      if entry then core.task(function() core.continue(entry) end) end
    end,
    d = action(function(w) M.review(w) end),
    D = action(function(w) M.review(w, "issue") end),
    v = action(function(w)
      core.open(w)
      require("util.pi_issue_edit").open(w)
    end, view_pending),
    x = action(function(w)
      core.task(function()
        if
          core.choose({ "Cancel", "Stop pi; keep worktree and session" }, "Stop " .. tasks.label(w) .. "?")
          == "Stop pi; keep worktree and session"
        then
          core.stop(w)
        end
      end)
    end),
    X = function()
      local entry = selected()
      if not entry then return end
      vim.cmd.close()
      core.task(function()
        if entry.pending then
          if core.choose({ "Cancel", "Delete local task file" },
            "Delete " .. tasks.label({
              source = "local", repo = entry.repo.repo, number = entry.pending.number,
            }) .. "?") == "Delete local task file" then
            tasks.delete(entry.pending)
            vim.notify("Deleted " .. tasks.label({
              source = "local", repo = entry.repo.repo, number = entry.pending.number,
            }), vim.log.levels.INFO, { title = "Pi Tasks" })
          end
        elseif core.choose({ "Cancel", "Delete task, worktree and session" },
          "Delete " .. tasks.label(entry) .. "? This removes its task file and all worktree changes.")
          == "Delete task, worktree and session" then
          core.delete(entry)
          vim.notify("Deleted " .. tasks.label(entry), vim.log.levels.INFO, { title = "Pi Tasks" })
        end
      end)
    end,
    r = refresh,
    ["?"] = function()
      local lines = {
        "# Task workspaces",
        "",
        "Enter: open code tab    p: start / focus pi",
        "new rows: written tasks without a workspace; p / Enter / 1-9 start them",
        "1-9: jump to that task's pi (or code tab when stopped)",
        "c: ask an idle pi to continue (e.g. after \"no changes\")",
        "R: restart with the current task text (new conversation, worktree kept)",
        "Space a a: switch task from anywhere    Space a g: start this task",
        "d: working diff        D: changes since the recorded base",
        "v: view / edit the task (GitHub uses a local draft)",
        "x: stop with confirmation; never delete work",
        "X: delete a local task (and its worktree/session) with confirmation",
        "r: refresh file counts i: choose tasks  n: new local task",
        "",
        "F6: hide / show pi, including from terminal input",
        "Space a s: paste context; Enter in pi submits it",
        "Space a r: paste a foreground reviewer request",
        "Local tasks: :write saves.",
        "",
        "Agent state does not verify tests or mark a task complete.",
      }
      if core.settings().github_enabled then
        lines[#lines + 1] = "g: GitHub issues. Drafts: Space a P confirms publishing."
      end
      show_help(lines)
    end,
    i = function()
      vim.api.nvim_win_close(win, false)
      M.tasks()
    end,
    n = function()
      vim.api.nvim_win_close(win, false)
      M.new_task()
    end,
    q = function() vim.cmd.close() end,
    ["<Esc>"] = function() vim.cmd.close() end,
  }
  for index = 1, 9 do
    maps[tostring(index)] = function()
      local entry = entries()[index]
      if not entry then return end
      vim.cmd.close()
      if entry.pending then start_pending(entry) else M.focus(entry) end
    end
  end
  if core.settings().github_enabled then
    maps.g = function()
      vim.api.nvim_win_close(win, false)
      M.issues()
    end
  end
  for key, fn in pairs(maps) do
    vim.keymap.set("n", key, fn, { buffer = dashboard, nowait = true })
  end
  draw()
  refresh()
end

function M.confirm_launch(lines)
  local thread = coroutine.running()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable, vim.bo[buf].bufhidden = false, "wipe"
  local win = vim.api.nvim_open_win(
    buf,
    true,
    vim.tbl_extend("force", geometry(100, #lines + 2), {
      relative = "editor",
      style = "minimal",
      border = "rounded",
      title = " Review Task Launch ",
      title_pos = "center",
      footer = " s start / Enter prepare only / q cancel ",
      footer_pos = "center",
    })
  )
  resize_with_editor(win, 100, #lines + 2)
  -- The base-ref prompt leaves insert mode pending; s/Enter/q are normal-mode keys.
  vim.cmd.stopinsert()
  vim.wo.wrap, vim.wo.linebreak, vim.wo.signcolumn = true, true, "no"
  vim.api.nvim_buf_set_extmark(buf, accents, 0, 0, { end_col = #lines[1], hl_group = "Title" })
  local finished = false
  local function finish(choice)
    if finished then return end
    finished = true
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    vim.schedule(function()
      local ok, err = coroutine.resume(thread, choice)
      if not ok then vim.notify(tostring(err), vim.log.levels.ERROR, { title = "Pi Tasks" }) end
    end)
  end
  for key, choice in pairs({ s = "Prepare and start", ["<CR>"] = "Prepare only", q = "Cancel", ["<Esc>"] = "Cancel" }) do
    vim.keymap.set("n", key, function() finish(choice) end, { buffer = buf, nowait = true })
  end
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function() finish("Cancel") end,
  })
  return coroutine.yield()
end

-- opts.review: ask for the base ref and show the launch review first. Otherwise start at once
-- from the default base (HEAD for local tasks); existing workspaces are reused and focused.
function M.launch(repo, issues, opts)
  opts = opts or {}
  core.task(function()
    local default = repo.source == "local" and "HEAD"
      or (repo.default_branch and ("origin/" .. repo.default_branch) or "")
    local ref = default
    if opts.review then ref = core.input("Base ref (locally cached; no automatic fetch): ", default) end
    if not ref then return end
    local sha = core.base(repo, ref)
    if not sha and core.unborn(repo) then
      error("This repository has no commits yet. Each task runs in a Git worktree branched from a commit, "
        .. "so commit your project first (for example: git add -A && git commit -m 'Initial commit'), "
        .. "then start the task again.", 0)
    end
    assert(sha, "Base ref is unavailable: " .. ref .. ". Fetch explicitly or choose an existing ref.")
    local summary = { repo.source == "local" and (repo.root .. " / local tasks") or (repo.host .. "/" .. repo.repo),
      "", "Base: " .. ref .. " (" .. sha:sub(1, 12) .. ")", "" }
    local trees = core.worktrees(repo.root)
    for _, issue in ipairs(issues) do
      local target = { source = repo.source, repo = repo.repo, number = issue.number }
      local ok, label = pcall(tasks.label, target)
      if not ok then
        summary[#summary + 1] = "Invalid selection: " .. core.clean(label)
      else
        summary[#summary + 1] = label .. " " .. core.clean(issue.title) .. " -> " .. tasks.branch(target)
        local path = tasks.worktree(repo, issue.number)
        for _, tree in ipairs(trees) do
          if tree.branch == tasks.branch(target) then path = tree.path end
        end
        summary[#summary + 1] = "   " .. path
      end
      summary[#summary + 1] = ""
    end
    summary[#summary + 1] = "Existing matching branches/worktrees will be reused; your main checkout is not changed."
    summary[#summary + 1] = "Start sends task context using pi-agent's configured default model. Limit: "
      .. core.settings().max_agents
      .. " live agents."
    local choice = opts.review and M.confirm_launch(summary) or "Prepare and start"
    if not choice or choice == "Cancel" then return end
    local failures, prepared, started = {}, 0, 0
    for _, issue in ipairs(issues) do
      local ok, err = pcall(function()
        local workspace = core.prepare(repo, issue, ref, true, sha)
        prepared = prepared + 1
        core.open(workspace)
        if choice == "Prepare and start" then
          local count = 0
          for _, job in pairs(core.jobs) do
            if not job.exited then count = count + 1 end
          end
          if count < core.settings().max_agents then
            core.start(workspace)
            started = started + 1
          else
            vim.notify(
              "Prepared " .. tasks.label(workspace) .. "; start from Space a w when a slot is free",
              vim.log.levels.INFO
            )
          end
        end
        core.refresh(workspace)
        core.changed()
      end)
      if not ok then failures[#failures + 1] = "#" .. issue.number .. ": " .. tostring(err) end
    end
    vim.notify(
      ("%d prepared; %d started%s"):format(
        prepared,
        started,
        #failures > 0 and ("\n" .. table.concat(failures, "\n")) or ""
      ),
      #failures > 0 and vim.log.levels.ERROR or vim.log.levels.INFO,
      { title = "Pi task launch" }
    )
  end)
end

function M.tasks(source, query, limit, repository)
  source = source or "local"
  local root = repository and repository.root or core.root()
  limit = limit or 50
  core.task(function()
    local repo = repository or core.repository(root, source)
    local items = tasks.list(repo, query, limit)
    for _, issue in ipairs(items) do
      issue.text = ("%d %s"):format(issue.number, core.clean(issue.title))
    end
    local title = repo.repo .. (source == "local" and " / Local Tasks" or " / GitHub Issues")
    if #items == 0 then
      title = (source == "local" and "No local tasks / "
        or (query and query ~= "" and "No matching open issues / " or "No open issues / ")) .. repo.repo
    end
    Snacks.picker({
      title = title,
      items = items,
      show_empty = true,
      format = "text",
      layout = {
        preset = "select",
        layout = {
          footer = "Enter start / Ctrl-d delete / Ctrl-b review / Ctrl-n new / Ctrl-o edit / ? help",
          footer_pos = "center",
        },
      },
      confirm = function(picker)
        local selected = picker:selected({ fallback = true })
        picker:close()
        if #selected > 0 then M.launch(repo, selected) end
      end,
      actions = {
        task_help = function()
          local lines = {
            source == "local" and "# Local tasks" or "# GitHub issues",
            "",
            "Enter: start pi on the selected task(s) now (base: HEAD)",
            "Ctrl-b: choose a base ref and review before starting / prepare only",
            "Ctrl-o: edit the task; GitHub uses a local draft",
            "Ctrl-d: delete selected local task(s), including worktrees and sessions",
            "Ctrl-n: create a local task",
            "Tab: select several tasks",
            "Ctrl-s: search    Ctrl-l: load 50 more",
            "",
            source == "local" and "Local tasks: :write saves. No publication step."
              or "GitHub drafts: :write saves locally; Space a P confirms publishing.",
          }
          if core.settings().github_enabled then
            lines[#lines + 1] = ":PiTasks github opens GitHub issues."
            lines[#lines + 1] = ":PiTaskImport / :PiTaskExport copy between sources."
          end
          show_help(lines)
        end,
        review_launch = function(picker)
          local selected = picker:selected({ fallback = true })
          picker:close()
          if #selected > 0 then M.launch(repo, selected, { review = true }) end
        end,
        delete_task = function(picker)
          local selected = picker:selected({ fallback = true })
          if source ~= "local" then
            return vim.notify("Only local tasks can be deleted", vim.log.levels.INFO, { title = "Pi Tasks" })
          end
          if core.choose({ "Cancel", "Delete selected local task(s)" },
            ("Delete %d task(s)? Their files, worktrees and sessions will be removed."):format(#selected))
            ~= "Delete selected local task(s)" then return end
          picker:close()
          core.task(function()
            for _, item in ipairs(selected) do
              local workspace = core.workspaces[vim.fn.sha256(repo.common .. "\0"
                .. tasks.identity(item)):sub(1, 24)]
              if workspace then
                core.delete(workspace)
              else
                tasks.delete(item)
              end
            end
            vim.notify(("Deleted %d local task(s)"):format(#selected), vim.log.levels.INFO, { title = "Pi Tasks" })
          end)
        end,
        view_issue = function(picker)
          local issue = picker:current()
          if not issue then return end
          picker:close()
          require("util.pi_issue_edit").open({
            host = repo.host, repo = repo.repo, number = issue.number, path = repo.root,
            source = repo.source, task_root = repo.task_root, task_file = issue.task_file,
          })
        end,
        server_search = function(picker)
          picker:close()
          core.task(function()
            local search = core.input(source == "local" and "Local task search: " or "GitHub issue search: ", query or "")
            if search then M.tasks(source, search, limit, repo) end
          end)
        end,
        more_issues = function(picker)
          picker:close()
          M.tasks(source, query, limit + 50, repo)
        end,
        new_task = function(picker)
          picker:close()
          M.new_task(nil, repo.root)
        end,
      },
      win = {
        input = {
          keys = {
            ["<C-s>"] = { "server_search", mode = { "n", "i" } },
            ["<C-l>"] = { "more_issues", mode = { "n", "i" } },
            ["<C-o>"] = { "view_issue", mode = { "n", "i" } },
            ["<C-b>"] = { "review_launch", mode = { "n", "i" } },
            ["<C-d>"] = { "delete_task", mode = { "n", "i" } },
            ["<C-n>"] = { "new_task", mode = { "n", "i" } },
            ["?"] = { "task_help", mode = "n" },
          },
        },
      },
    })
  end)
end

function M.issues(query, limit, repository) return M.tasks("github", query, limit, repository) end

function M.new_task(title, root)
  core.task(function()
    local repo = core.repository(root or core.root(), "local")
    if not title then return require("util.pi_issue_edit").compose(repo) end
    local target = tasks.create(repo, title)
    require("util.pi_issue_edit").open(target)
  end)
end

function M.delete_current()
  local info = vim.b.pi_issue_draft
  local workspace = core.current()
  local target = info and info.target or workspace
  assert(target and target.source == "local", "Open or activate a local task before deleting it")
  core.task(function()
    if core.choose({ "Cancel", "Delete local task" },
      "Delete " .. tasks.label(target) .. "? This cannot be undone.") ~= "Delete local task" then return end
    local active = workspace and core.workspaces[vim.fn.sha256(
      workspace.common .. "\0" .. tasks.identity(target)
    ):sub(1, 24)]
    if active then core.delete(active) else tasks.delete(target) end
    vim.notify("Deleted " .. tasks.label(target), vim.log.levels.INFO, { title = "Pi Tasks" })
  end)
end

local copying = false
local function copy_task(fn)
  return core.task(function()
    assert(not copying, "A task copy is already in progress")
    copying = true
    local ok, err = pcall(fn)
    copying = false
    if not ok then error(err, 0) end
  end)
end

function M.import_task(number)
  local current = core.current()
  local root = core.root()
  return copy_task(function()
    local local_repo = core.repository(root, "local")
    local target
    if not number and current and current.source ~= "local" then
      target = current
    else
      local repo = core.repository(root, "github")
      number = number or core.input("GitHub issue number to import: ", "")
      if not number then return end
      assert(tostring(number):match("^%d+$") and tonumber(number) > 0, "Enter a positive GitHub issue number")
      target = { source = "github", repo = repo.repo, host = repo.host, number = tonumber(number), path = repo.root }
    end
    local issue = tasks.get(target)
    if core.choose({ "Cancel", "Import as local task" },
      "Copy " .. tasks.label(target) .. " into " .. local_repo.root .. "/.tasks/?") ~= "Import as local task" then return end
    local imported = tasks.create(local_repo, issue.title, issue.body or "")
    require("util.pi_issue_edit").open(imported)
    vim.notify("Imported " .. tasks.label(target) .. " as " .. tasks.label(imported)
      .. "; the GitHub issue is unchanged", vim.log.levels.INFO)
  end)
end

function M.export_task()
  local info = vim.b.pi_issue_draft
  local target = info and info.target or core.current()
  return copy_task(function()
    assert(target and target.source == "local", "Open a local task or activate its workspace before exporting")
    local repo = core.repository(target.task_root, "github")
    local path = tasks.file(target)
    local buf = vim.fn.bufnr(path)
    if buf >= 0 and vim.api.nvim_buf_is_loaded(buf) then
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("checktime")
        vim.cmd("silent update")
      end)
    end
    local task = tasks.get(target)
    if core.choose({ "Cancel", "Create GitHub issue" },
      "Publish " .. tasks.label(target) .. " as a NEW issue in " .. repo.host .. "/" .. repo.repo .. "?")
      ~= "Create GitHub issue" then return end
    local current_task = tasks.get(target)
    assert(current_task.title == task.title and current_task.body == task.body
      and (buf < 0 or not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modified),
      "Local task changed during confirmation; review it and export again")
    local created = tasks.create(repo, task.title, task.body)
    vim.notify("Created " .. tasks.label(created) .. ": " .. created.url
      .. "\nLocal task, worktree and session are unchanged. Repeating export creates another issue.",
      vim.log.levels.INFO)
  end)
end

function M.install()
  if vim.fn.executable("npm") ~= 1 then
    return vim.notify("npm is required to install pi-subagents", vim.log.levels.ERROR)
  end
  core.task(function()
    local result = core.run({ "npm", "ci", "--ignore-scripts", "--omit=dev" }, core.path())
    vim.notify(
      "Pinned pi-subagents installed. Use Space a i to choose local tasks.\n" .. vim.trim(result.stdout),
      vim.log.levels.INFO
    )
  end)
end

function M.setup()
  core.setup()
  core.load()
  vim.api.nvim_create_user_command("PiTasks", function(opts)
    M.tasks(opts.args ~= "" and opts.args or "local")
  end, { nargs = "?", complete = function() return { "local", "github" } end, desc = "Choose local or GitHub tasks" })
  vim.api.nvim_create_user_command("PiTaskNew", function(opts)
    M.new_task(opts.args ~= "" and opts.args or nil)
  end, { nargs = "*", desc = "Create a local Markdown task" })
  vim.api.nvim_create_user_command("PiTaskRestart", M.restart_current,
    { desc = "Restart the task with its current description in a new conversation" })
  vim.api.nvim_create_user_command("PiTaskView", function() require("util.pi_issue_edit").open() end,
    { desc = "View / edit the active task" })
  vim.api.nvim_create_user_command("PiTaskEdit", function() require("util.pi_issue_edit").edit() end,
    { desc = "Ask the active pi-agent to revise the task" })
  vim.api.nvim_create_user_command("PiTaskDelete", M.delete_current,
    { desc = "Delete the current local task and its workspace" })
  vim.api.nvim_create_user_command("PiTaskImport", function(opts)
    M.import_task(opts.args ~= "" and opts.args or nil)
  end, { nargs = "?", desc = "Copy a GitHub issue into a local task after confirmation" })
  vim.api.nvim_create_user_command("PiTaskExport", M.export_task,
    { desc = "Copy a local task to a new GitHub issue after confirmation" })
  vim.api.nvim_create_user_command(
    "PiIssues",
    function(opts) M.issues(opts.args) end,
    { nargs = "?", desc = "Choose GitHub issues" }
  )
  vim.api.nvim_create_user_command("PiWorkspaces", M.dashboard, { desc = "Pi task workspace dashboard" })
  vim.api.nvim_create_user_command("PiIssuesSetup", M.install, { desc = "Install pinned pi extension dependencies" })
  vim.api.nvim_create_user_command("PiQuit", core.quit, { desc = "Confirm stopping managed agents and quit safely" })
  vim.api.nvim_create_user_command("PiIssueView", function() require("util.pi_issue_edit").open() end,
    { desc = "View / edit the active GitHub issue draft" })
  vim.api.nvim_create_user_command("PiIssuePublish", function() require("util.pi_issue_edit").publish() end,
    { desc = "Publish the issue draft after confirmation" })
  vim.api.nvim_create_user_command("PiIssueEdit", function() require("util.pi_issue_edit").edit() end,
    { desc = "Ask the active pi-agent to revise the issue draft" })
  vim.api.nvim_create_user_command("PiIssueReload", function()
    local info = vim.b.pi_issue_draft
    require("util.pi_issue_edit").open(info and info.target or nil, true)
  end, { desc = "Reload the GitHub issue after confirming draft replacement" })
  vim.api.nvim_create_user_command(
    "PiIssueDiff",
    function(opts) M.review(core.current(), opts.args == "issue" and "issue" or "working") end,
    {
      nargs = "?",
      complete = function() return { "working", "issue" } end,
    }
  )
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("pi_issues_ui", { clear = true }),
    pattern = "PiIssuesChanged",
    callback = draw,
  })
end

return M
