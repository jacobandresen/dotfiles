local M = {}
local core = require("taskbay.core")
local tasks = require("taskbay.store")
local remote = require("taskbay.remote")
local review = require("taskbay.review")
local dashboard
local dashboard_rows = {}
local accents = vim.api.nvim_create_namespace("taskbay_panel")

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

-- Centered floating window for a scratch buffer; keeps its size on VimResized.
local function float(buf, width, height, extra, redraw)
  local win = vim.api.nvim_open_win(buf, true, vim.tbl_extend("force", geometry(width, height), extra))
  resize_with_editor(win, width, height, redraw)
  return win
end

local function show_help(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden, vim.bo[buf].filetype, vim.bo[buf].modifiable = "wipe", "markdown", false
  local back = vim.api.nvim_get_current_win() -- the panel; closing the help returns to it
  local win = float(buf, 72, #lines, {
    style = "minimal", border = "rounded", title = " Task Help ", title_pos = "center",
    footer = " q close ", footer_pos = "center",
  })
  vim.wo[win].wrap, vim.wo[win].linebreak = true, true
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      vim.api.nvim_win_close(win, false)
      if vim.api.nvim_win_is_valid(back) then vim.api.nvim_set_current_win(back) end
    end, { buffer = buf, nowait = true })
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

-- Nerd Font glyphs for agent states; the plain text always follows.
local glyph = {
  starting = "\u{f110}", working = "\u{f110}", waiting = "\u{f252}", unknown = "\u{f059}",
  idle = "\u{f017}", ["no changes"] = "\u{f056}", stopping = "\u{f011}", stopped = "\u{f011}",
  finished = "\u{f00c}", error = "\u{f06a}", missing = "\u{f06a}", new = "\u{f067}",
}
local function icon(status) return (glyph[status] or "\u{f059}") end

function M.tabline()
  local parts = {}
  for i, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local workspace = core.workspaces[vim.t[tab].taskbay_workspace or ""]
    local label = workspace
        and (icon(core.status(workspace)) .. " "
          .. vim.fs.basename(workspace.repo) .. (workspace.source == "local" and "/" or "#")
          .. (tasks.name(workspace, 22) or ("task-" .. workspace.number)) .. " " .. core.status(workspace))
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
  vim.o.tabline = "%!v:lua.require'taskbay.ui'.tabline()"
end

function M.statusline()
  local workspace = core.current()
  if not workspace then return "" end
  local job = core.jobs[workspace.id]
  local model = job and job.model or "pending"
  return safe(("\u{f085} %s %s | %s | %s"):format(core.agent().title, tasks.label(workspace), core.status(workspace), model))
end

-- Jump to a task: its agent terminal while the agent runs, otherwise its code tab.
function M.focus(workspace)
  core.task(function()
    core.validate(workspace)
    local job = core.jobs[workspace.id]
    if job and not job.exited then core.show(workspace) else core.open(workspace) end
  end)
end

-- Common Git dir of the repository the panel is opened from; workspaces of other
-- repositories are scoped out of the task list. Nil outside any Git repository,
-- in which case every workspace is still shown.
local function current_common()
  local local_root = core.root()
  local git_path = vim.fs.find(".git", { upward = true, path = local_root, limit = 1 })[1]
  if not git_path then return nil end
  local stat = vim.uv.fs_stat(git_path)
  if stat and stat.type == "file" then -- a linked worktree's .git points at the main checkout
    local gitdir = (vim.fn.readfile(git_path, "", 1)[1] or ""):gsub("^gitdir:%s*", ""):gsub("%s+$", "")
    return core.real(gitdir:match("^(.*)/worktrees/[^/]+") or gitdir)
  end
  return core.real(git_path)
end

local function ordered()
  local common = current_common()
  local items = {}
  for _, workspace in pairs(core.workspaces) do
    if not common or workspace.common == common then items[#items + 1] = workspace end
  end
  table.sort(items, function(a, b) return a.repo == b.repo and a.number < b.number or a.repo < b.repo end)
  return items
end

-- Dashboard row color for each agent status; unknown statuses stay dim.
local status_groups = {
  error = "DiagnosticError",
  missing = "DiagnosticError",
  waiting = "DiagnosticWarn",
  ["no changes"] = "DiagnosticWarn",
  working = "DiagnosticInfo",
  new = "DiagnosticHint",
  finished = "Comment",
}

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
    return { repo = repo, items = tasks.list(repo, nil, 200) }
  end)
  pending = ok and result or { items = {} }
end
local function start_pending(entry)
  local item = entry.pending
  M.launch(entry.repo, { number = item.number, title = item.title, task_file = item.task_file })
end

-- Dashboard paging: the panel shows one page of rows at a time.
local page, page_count, visible_rows = 1, 1, {}

-- When set, the next draw focuses this entry ("new:<number>" for a task that
-- was just written); kept until a draw could actually land on the row.
local reveal_id
local function reveal(entry_key) reveal_id = entry_key end

-- The footer names only what the row under the cursor can do.
local function row_keys(entry)
  if not entry then return "" end
  if entry.pending then return "Enter start  v edit  f fields  X delete" end
  local job = core.jobs[entry.id]
  if core.status(entry) == "finished" then return "Enter open  d diff  X delete" end
  if job and not job.exited then return "Enter agent  c continue  x stop  d diff  m finish" end
  return "Enter open  p resume  R restart  d diff  m finish"
end
local function set_footer()
  for _, win in ipairs(vim.fn.win_findbuf(dashboard)) do
    local keys = row_keys(dashboard_rows[vim.api.nvim_win_get_cursor(win)[1]])
    local footer = " " .. keys .. (keys ~= "" and "  ·  " or "") .. "n new  ? help "
    vim.api.nvim_win_set_config(win, { footer = footer, footer_pos = "center" })
  end
end

local function help_lines()
  local lines = {
    "# Task workspaces",
    "",
    "Enter / 1-9  go to the task (a new task starts)",
    "p  start / resume the agent    x  stop it (work is kept)",
    "c  ask an idle agent to go on  R  restart in a new conversation",
    "m  finish: commit, merge into your checkout, mark finished",
    "d  working diff                D  diff since the recorded base",
    "v  task text                   f  fields (labels, assignees, ...)",
    "X  delete the task and its worktree",
    "n  new task    r  refresh    [ ]  pages    q  close",
    "",
    "## Outside the panel",
    core.key("agent") .. "  start / show / hide the agent    " .. core.key("toggle") .. "  the same, from the terminal",
    core.key("quit") .. "  stop agents and quit",
    "In a task tab:   " .. core.key("task") .. "  task text    " .. core.key("review") .. "  reviewer subagent",
    "With an agent running: " .. core.key("send") .. "  send file / selection",
    "",
    "In a task file: :write saves, Tab shows fields, " .. core.key("revise") .. " asks the agent to revise.",
    "\"finished\" means merged into your main checkout; the agent's status is not task completion.",
  }
  local tracker = core.remote().title
  lines[#lines + 1] = core.settings().remote_enabled and (tracker .. ": e exports a task, I imports issues.")
    or (tracker .. " is off; " .. core.key("remote") .. " turns on e (export) and I (import).")
  return lines
end

local function draw()
  if not dashboard or not vim.api.nvim_buf_is_valid(dashboard) then return end
  local revealing = reveal_id ~= nil
  local current_id = reveal_id
  reveal_id = nil
  if not current_id then
    for _, win in ipairs(vim.fn.win_findbuf(dashboard)) do
      local row = vim.api.nvim_win_get_cursor(win)[1]
      current_id = dashboard_rows[row] and entry_id(dashboard_rows[row])
    end
  end
  local matched = false
  local all = entries()
  local waiting = 0
  for _, job in pairs(core.jobs) do
    if not job.exited and job.activity == "waiting" then waiting = waiting + 1 end
  end
  local active = core.live()
  -- Unfinished tasks first; the index tiebreak keeps the order stable across redraws.
  local sortable = {}
  for index, entry in ipairs(all) do
    sortable[index] = { entry = entry, index = index, finished = not entry.pending and core.status(entry) == "finished" }
  end
  table.sort(sortable, function(a, b)
    if a.finished ~= b.finished then return b.finished end
    return a.index < b.index
  end)
  local page_size = math.max(5, vim.o.lines - 16)
  page_count = math.max(1, math.ceil(#sortable / page_size))
  -- A revealed row brings its page into view.
  for i, item in ipairs(revealing and sortable or {}) do
    if entry_id(item.entry) == current_id then page = math.ceil(i / page_size) end
  end
  page = math.min(math.max(page, 1), page_count)
  visible_rows = {}
  for i = (page - 1) * page_size + 1, math.min(page * page_size, #sortable) do
    visible_rows[#visible_rows + 1] = sortable[i].entry
  end
  local wins = vim.fn.win_findbuf(dashboard)
  local width = #wins > 0 and vim.api.nvim_win_get_width(wins[1]) or 100
  local title_width = math.max(8, width - 32)
  -- Columns: index, status (padded by display width: glyphs are wider in bytes), files, task.
  local status_width = 14
  local function row(index, status, files, task)
    return ("%2s  %s%5s   %s"):format(index, status .. (" "):rep(status_width - vim.fn.strdisplaywidth(status)), files, task)
  end
  local lines = {
    ("  %d of %d agents running%s  ·  %d tasks%s"):format(active, core.settings().max_agents,
      waiting > 0 and ("  ·  %d waiting for you"):format(waiting) or "", #all,
      page_count > 1 and ("  ·  page %d/%d  [ ]"):format(page, page_count) or ""),
    "",
    row("", "STATUS", "FILES", "TASK"),
  }
  dashboard_rows = {}
  local statuses = {}
  local selected = 4
  for index, entry in ipairs(visible_rows) do
    local new = entry.pending
    local status = new and "new" or core.status(entry)
    statuses[#lines + 1] = status
    local done, total = entry.actions_done, entry.actions_total
    if new then done, total = new.actions.done, new.actions.total end
    local progress = (total or 0) > 0 and ("  %d/%d"):format(done, total) or ""
    lines[#lines + 1] = row(
      index <= 9 and tostring(index) or "",
      icon(status) .. " " .. status,
      new and "-" or (entry.refreshing and "..." or tostring(entry.files or "?")),
      ("#%d %s%s"):format(new and new.number or entry.number, clip(new and new.title or entry.title, title_width), progress)
    )
    dashboard_rows[#lines] = entry
    if entry_id(entry) == current_id then
      selected = #lines
      matched = true
    end
  end
  -- A reveal before its row loaded (panel closed at write time) survives until it can apply.
  if revealing and not matched then reveal_id = current_id end
  if #all == 0 then
    lines[#lines + 1] = vim.tbl_count(core.workspaces) > 0
        and "  No tasks in this repository; the existing task workspaces belong to other checkouts."
      or "  No tasks yet. Press n to write one."
  end
  vim.bo[dashboard].modifiable = true
  vim.api.nvim_buf_set_lines(dashboard, 0, -1, false, lines)
  vim.bo[dashboard].modifiable = false
  vim.api.nvim_buf_clear_namespace(dashboard, accents, 0, -1)
  local function highlight(row, col, group, last)
    vim.api.nvim_buf_set_extmark(dashboard, accents, row, col, { end_col = last or #lines[row + 1], hl_group = group })
  end
  highlight(0, 0, "Comment")
  highlight(2, 0, "Comment")
  for row, status in pairs(statuses) do
    highlight(row - 1, 4, status_groups[status] or "Comment", 4 + #(icon(status) .. " " .. status))
  end
  for _, win in ipairs(vim.fn.win_findbuf(dashboard)) do
    if vim.api.nvim_win_get_height(win) < #lines and vim.api.nvim_win_get_config(win).relative ~= "" then
      vim.api.nvim_win_set_config(win, geometry(112, #lines))
    end
    vim.api.nvim_win_set_cursor(win, { math.min(selected, #lines), 0 })
  end
  set_footer()
end

-- Re-read written tasks and redraw; tasks may have been written since the panel opened.
local function reload() core.task(function() load_pending(); draw() end) end
local function panel_open() return dashboard and vim.api.nvim_buf_is_valid(dashboard) and #vim.fn.win_findbuf(dashboard) > 0 end

function M.dashboard()
  core.load()
  if panel_open() then
    vim.api.nvim_set_current_win(vim.fn.win_findbuf(dashboard)[1])
    return reload()
  end
  dashboard = vim.api.nvim_create_buf(false, true)
  vim.bo[dashboard].bufhidden = "wipe"
  vim.bo[dashboard].filetype = "taskbay"
  vim.api.nvim_buf_set_name(dashboard, "taskbay://panel/" .. dashboard)
  local height = math.max(10, vim.tbl_count(core.workspaces) + 7)
  local size = geometry(112, height)
  local win = float(dashboard, 112, height, {
    style = "minimal",
    border = "rounded",
    title = " \u{f07b} Task Workspaces ",
    title_pos = "center",
    -- draw() replaces this with only the currently applicable keys.
    footer = "",
    footer_pos = "center",
  }, draw)
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
    reload()
    draw()
  end
  -- The editor/fields target for a "new" row: a written local task with no workspace yet.
  local function draft_target(entry)
    return {
      source = "local", task_root = entry.repo.root, number = entry.pending.number,
      task_file = entry.pending.task_file, repo = entry.repo.repo, host = "local", path = entry.repo.root,
    }
  end
  local function popup(fn)
    return function()
      vim.api.nvim_win_close(win, false)
      fn()
    end
  end
  local edit, fields = require("taskbay.editor"), require("taskbay.fields")
  -- Enter and 1-9 go to a task: a new one starts, a live one shows its agent, others open their tab.
  local function go(entry)
    if not entry then return end
    vim.cmd.close()
    if entry.pending then start_pending(entry) else M.focus(entry) end
  end
  local function run(fn, on_new) return action(function(w) core.task(function() fn(w) end) end, on_new) end
  local maps = {
    ["<CR>"] = function() go(selected()) end,
    p = run(core.start, start_pending),
    R = run(core.restart),
    m = run(core.finish),
    -- Stopping never deletes work; no confirmation needed.
    x = run(core.stop),
    c = function()
      local entry = selected()
      if entry and entry.pending then return not_started() end
      if entry then core.task(function() core.continue(entry) end) end
    end,
    d = action(function(w) review.review(w) end),
    D = action(function(w) review.review(w, "issue") end),
    v = action(function(w)
      core.open(w)
      edit.open(w)
    end, function(entry) edit.open(draft_target(entry)) end),
    f = action(function(w) core.task(function() fields.open(w) end) end,
      function(entry) fields.open(draft_target(entry)) end),
    X = function()
      local entry = selected()
      if not entry then return end
      vim.cmd.close()
      core.task(function()
        local new = entry.pending ~= nil
        local label = tasks.label(new and vim.tbl_extend("force", draft_target(entry), { title = entry.pending.title }) or entry)
        local choice = new and "Delete local task file" or "Delete task, worktree and session"
        if core.choose({ "Cancel", choice }, "Delete " .. label
          .. (new and "?" or "? This removes its task file and all worktree changes.")) ~= choice then return end
        if new then tasks.delete(entry.pending) else core.delete(entry) end
        vim.notify("Deleted " .. label, vim.log.levels.INFO, { title = "Taskbay" })
      end)
    end,
    n = popup(function() M.new_task(nil, nil, true) end),
    r = refresh,
    ["?"] = function() show_help(help_lines()) end,
    q = function() vim.cmd.close() end,
    ["<Esc>"] = function() vim.cmd.close() end,
  }
  for index = 1, 9 do
    maps[tostring(index)] = function() go(visible_rows[index]) end
  end
  maps["["] = function() page = page > 1 and page - 1 or page_count; draw() end
  maps["]"] = function() page = page < page_count and page + 1 or 1; draw() end
  -- Tracker actions exist only while the integration is on; issues enter through import.
  if core.settings().remote_enabled then
    maps.e = action(remote.export_task, function(entry) remote.export_task(draft_target(entry)) end)
    maps.I = popup(remote.import_task)
  end
  local desc = {
    ["<CR>"] = "Go to Task", p = "Start / Resume Agent", R = "Restart in a New Conversation", c = "Continue",
    m = "Finish: Commit, Merge, Mark Finished", d = "Working Diff", D = "Diff vs Recorded Base", x = "Stop Agent",
    v = "Task Text", f = "Fields", r = "Refresh", e = "Export to a New " .. core.remote().title .. " Issue", I = "Import " .. core.remote().title .. " Issues",
    X = "Delete Task", n = "New Task", ["?"] = "Help", q = "Close", ["<Esc>"] = "Close",
  }
  for key, fn in pairs(maps) do
    vim.keymap.set("n", key, fn, { buffer = dashboard, nowait = true, desc = desc[key] })
  end
  -- The panel is read-only: keep insert keys from entering insert mode.
  for _, key in ipairs({ "i", "a" }) do vim.keymap.set("n", key, "<Nop>", { buffer = dashboard }) end
  vim.api.nvim_create_autocmd("CursorMoved", { buffer = dashboard, callback = function() set_footer() end })
  draw()
  refresh()
end

-- Start a written task: its worktree branches from HEAD, and the agent starts when a slot is free.
function M.launch(repo, issue)
  core.task(function()
    local sha = core.base(repo, "HEAD")
    if not sha and core.unborn(repo) then
      error("This repository has no commits yet. Each task runs in a Git worktree branched from a commit, "
        .. "so commit your project first (for example: git add -A && git commit -m 'Initial commit'), "
        .. "then start the task again.", 0)
    end
    assert(sha, "HEAD does not resolve to a commit")
    local workspace = core.prepare(repo, issue, "HEAD", true, sha)
    core.open(workspace)
    if core.live() < core.settings().max_agents then
      core.start(workspace)
    else
      vim.notify("Prepared " .. tasks.label(workspace) .. "; start it with p in " .. core.key("panel") .. " when a slot is free",
        vim.log.levels.INFO, { title = "Taskbay" })
    end
    core.refresh(workspace)
    core.changed()
  end)
end

-- A written task becomes selectable in the workspace panel immediately: the
-- panel's pending rows are reloaded and redrawn, focused on the new task.
function M.task_created(target)
  reveal("new:" .. target.number)
  if panel_open() then reload() end
end

-- opts.from_panel: reopen the workspace panel on the new row after :write, so
-- selecting the issue happens in the panel.
function M.new_task(title, root, from_panel)
  core.task(function()
    local repo = core.repository(root or core.root(), "local")
    if not title then return require("taskbay.editor").compose(repo, from_panel and M.dashboard or nil) end
    local target = tasks.create(repo, title)
    require("taskbay.editor").open(target)
    M.task_created(target)
    if from_panel then M.dashboard() end
  end)
end

-- One-time agent setup (:TaskbaySetup), when the agent driver has any.
function M.install()
  local agent = core.agent()
  if not agent.install then return vim.notify(agent.title .. " needs no setup", vim.log.levels.INFO) end
  core.task(function()
    vim.notify(agent.install() .. "\nStart tasks from the workspace panel (" .. core.key("panel") .. ").", vim.log.levels.INFO)
  end)
end

-- Runtime switch for the issue tracker integration (Space a G / :TaskbayRemote); open
-- panels are closed so the next open rebuilds their keys and footers.
function M.toggle_remote()
  vim.g.taskbay = vim.tbl_extend("force", vim.g.taskbay or {}, { remote_enabled = not core.settings().remote_enabled })
  vim.notify(
    "Taskbay " .. core.remote().title .. " integration " .. (core.settings().remote_enabled and "enabled" or "disabled"),
    vim.log.levels.INFO,
    { title = "Taskbay" }
  )
  -- The dashboard reuses a loaded buffer; close it so the next open rebuilds
  -- its mappings (and which-key entries) for the new state.
  if dashboard and vim.api.nvim_buf_is_valid(dashboard) then
    for _, win in ipairs(vim.fn.win_findbuf(dashboard)) do
      vim.api.nvim_win_close(win, true)
    end
  end
end

function M.setup()
  core.setup()
  core.load()
  -- Context-bound keys exist (and are listed by which-key) only while they work:
  -- task keys need a task in the current tab or buffer, sending needs a live agent.
  -- Jobs and buffers change outside this module, so a light poll plus BufEnter
  -- keeps the mappings in sync.
  local edit = require("taskbay.editor")
  local agents = require("taskbay.terminal")
  local function task_selected()
    local info = vim.b.taskbay_task
    return core.current() ~= nil or (info and info.target) ~= nil
  end
  local keys = core.settings().keys
  local function contextual_maps()
    return {
      { keys.task, edit.open, "Task Text", task_selected() },
      { keys.review, agents.review, "Review Task with a Subagent", task_selected() },
      -- Sending context needs a live agent anywhere (a task's or a standalone terminal).
      { keys.send, function() agents.send(false) end, "Send File to the Agent", agents.available() },
      { keys.send, function() agents.send(true) end, "Send Selection to the Agent", agents.available(), "x" },
    }
  end
  local function refresh_dynamic_maps()
    for _, map in ipairs(contextual_maps()) do
      local mode = map[5] or "n"
      -- maparg in dict mode yields an EMPTY table when nothing is mapped.
      local mapped = vim.fn.maparg(map[1], mode, false, true)
      local exists = type(mapped) == "table" and next(mapped) ~= nil
      if map[4] and not exists then
        vim.keymap.set(mode, map[1], map[2], { desc = map[3] })
      elseif not map[4] and exists then
        pcall(vim.keymap.del, mode, map[1])
      end
    end
  end
  refresh_dynamic_maps()
  -- Keys that always work; the panel holds every per-task action.
  for _, map in ipairs({
    { keys.panel, M.dashboard, "Task Workspaces" },
    { keys.new, function() M.new_task() end, "New Task" },
    { keys.agent, function() agents.toggle(true) end, "Agent: Start / Show / Hide" },
    { keys.toggle, function()
      vim.cmd.stopinsert()
      agents.toggle()
    end, "Hide / Show the Agent", { "n", "t" } },
    { keys.quit, core.quit, "Stop Agents and Quit" },
    { keys.remote, M.toggle_remote, "Toggle the Issue Tracker" },
  }) do
    vim.keymap.set(map[4] or "n", map[1], map[2], { desc = map[3] })
  end
  local switch_timer = vim.uv.new_timer()
  switch_timer:start(500, 2000, vim.schedule_wrap(refresh_dynamic_maps))
  -- Task actions live in the workspace panel; commands cover what has no key there.
  local command = vim.api.nvim_create_user_command
  command("Taskbay", M.dashboard, { desc = "Task workspace panel" })
  command("TaskbayNew", function(opts) M.new_task(opts.args ~= "" and opts.args or nil) end,
    { nargs = "*", desc = "Create a local Markdown task" })
  command("TaskbayRemote", M.toggle_remote, { desc = "Enable / disable the issue tracker integration" })
  command("TaskbayImport", function(opts) remote.import_task(opts.args ~= "" and opts.args or nil) end,
    { nargs = "?", desc = "Copy a remote issue into a local task after confirmation" })
  command("TaskbayExport", function() remote.export_task() end, { desc = "Copy a local task to a new remote issue after confirmation" })
  command("TaskbayReload", function()
    local info = vim.b.taskbay_task
    edit.open(info and info.target or nil, true)
  end, { desc = "Reload the remote issue after confirming draft replacement" })
  command("TaskbaySetup", M.install, { desc = "One-time setup of the coding agent" })
  command("TaskbayQuit", core.quit, { desc = "Confirm stopping managed agents and quit safely" })
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("taskbay_ui", { clear = true }),
    pattern = "TaskbayChanged",
    callback = draw,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("taskbay_maps", { clear = true }),
    callback = function() vim.schedule(refresh_dynamic_maps) end,
  })
end

return M
