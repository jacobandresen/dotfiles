local M = {}
local core = require("taskbay.core")
local tasks = require("taskbay.store")
local fields = require("taskbay.fields")
local publishing = {}

local identity, fetch = tasks.identity, tasks.get

local function paths(target)
  if target.source == "local" then return tasks.file(target) end
  local id = vim.fn.sha256(identity(target))
  local directory = core.settings().state_dir .. "/issue-drafts/" .. id
  return directory .. "/issue.md", directory .. "/baseline.json"
end
M.paths = paths -- also used by the Fields tab for remote draft baselines

local function refresh(target, title)
  for _, workspace in pairs(core.workspaces) do
    if identity(workspace) == identity(target) then
      workspace.title = core.clean(title)
      core.save(workspace)
    end
  end
  core.changed()
end

local function read(path)
  return table.concat(vim.fn.readfile(path), "\n")
end

-- Pick up on-disk changes, then write pending buffer edits.
function M.save(buf)
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("checktime")
    vim.cmd("silent update")
  end)
end

local function draft(buf)
  assert(vim.api.nvim_buf_is_valid(buf), "Task buffer was closed")
  local info = vim.b[buf].taskbay_task
  assert(info, "Open a task with " .. core.key("task") .. " first")
  return info
end

function M.open(target, reload)
  target = target or core.current()
  if not target then
    return vim.notify("Choose a task in " .. core.key("panel") .. " first", vim.log.levels.WARN)
  end
  core.task(function()
    local path, baseline = paths(target)
    local local_task = target.source == "local"
    local previous = vim.uv.fs_stat(path) and read(path)
    local buf = vim.fn.bufnr(path)
    local tick = buf >= 0 and vim.api.nvim_buf_get_changedtick(buf)
    if reload and core.choose({ "Cancel", "Replace local draft" },
      "Discard buffer edits and reload " .. identity(target)
        .. (local_task and " from disk?" or (" from " .. tasks.driver(target).title .. "?"))) ~= "Replace local draft" then
      return
    end
    local fetched = not local_task and (reload or not vim.uv.fs_stat(path))
    if fetched then
      local issue = fetch(target)
      assert(buf < 0 or vim.api.nvim_buf_get_changedtick(buf) == tick,
        "Draft changed while fetching; no local edits were replaced")
      assert((vim.uv.fs_stat(path) and read(path)) == previous,
        "Draft changed on disk while fetching; no local edits were replaced")
      core.write(path, tasks.text(issue.title, issue.body))
      -- The full issue snapshot (labels, assignees, milestone, comments, ...)
      -- stays in the local baseline: editing or publishing the draft never
      -- drops information from the original issue.
      core.write(baseline, vim.json.encode(
        { target = target, title = issue.title, body = issue.body or "", url = issue.url, issue = issue }))
    end
    if local_task then fetch(target) end -- fails early on a missing or unreadable task file
    if (reload or fetched) and buf >= 0 and vim.api.nvim_buf_is_loaded(buf) then
      vim.api.nvim_buf_call(buf, function() vim.cmd("silent edit!") end)
    end
    local info = { target = target }
    if not local_task then
      assert(vim.uv.fs_stat(baseline), "Draft baseline is missing; use :TaskbayReload to reload explicitly")
      info = core.read_json(baseline)
    end
    assert(identity(info.target) == identity(target), "Task identity does not match")
    info.target = target
    buf = vim.fn.bufadd(path)
    vim.fn.bufload(buf)
    vim.b[buf].taskbay_task = info
    vim.bo[buf].buflisted, vim.bo[buf].filetype, vim.bo[buf].autoread = true, "markdown", true
    vim.api.nvim_buf_call(buf, function() vim.cmd("checktime") end)
    -- Stay in the task's own tab even when the file is still shown where it was written.
    local tab = vim.api.nvim_get_current_tabpage()
    local windows = vim.tbl_filter(function(win) return vim.api.nvim_win_get_tabpage(win) == tab end,
      vim.fn.win_findbuf(buf))
    if #windows > 0 then
      vim.api.nvim_set_current_win(windows[1])
    else
      vim.cmd("botright vsplit")
      vim.api.nvim_win_set_buf(0, buf)
    end
    -- Two tabs: Task (this buffer: title, body, relations) and Fields.
    vim.wo.winbar = local_task
        and "\u{f0f6} Task  ·  :write save  ·  Tab fields  ·  " .. core.key("revise") .. " ask agent  ·  " .. core.key("panel") .. " panel "
      or tasks.driver(target).glyph .. " " .. tasks.driver(target).title .. " draft  ·  :write save locally  ·  Tab fields  ·  " .. core.key("publish") .. " publish  ·  " .. core.key("revise") .. " ask agent "
    fields.decorate(buf, target)
    if local_task then
      vim.api.nvim_create_autocmd("BufWritePost", {
        group = vim.api.nvim_create_augroup("taskbay_task_" .. buf, { clear = true }),
        buffer = buf,
        callback = function()
          if vim.b[buf].taskbay_renaming then return end
          core.task(function()
            M.follow_rename(buf, target)
            refresh(target, fetch(target).title)
            fields.decorate(buf, target)
            for _, workspace in pairs(core.workspaces) do
              if workspace.started and identity(workspace) == identity(target) then
                local job = core.jobs[workspace.id]
                vim.notify("Task updated. In " .. core.key("panel") .. ", R restarts " .. tasks.label(workspace) .. " with it"
                  .. ((job and not job.exited) and "; the running agent keeps the old text until then."
                    or "; p resumes and sends it."), vim.log.levels.INFO)
              end
            end
          end)
        end,
      })
    else
      vim.keymap.set("n", core.settings().keys.publish, function() M.publish(buf) end,
        { buffer = buf, desc = "Publish Issue Draft (Confirm)" })
    end
    -- Tab flips to the Fields tab; Tab there flips back.
    vim.keymap.set("n", "<Tab>", function() fields.open(target) end,
      { buffer = buf, nowait = true, desc = "Fields Tab" })
    vim.keymap.set("n", core.settings().keys.revise, function() M.agent(buf) end,
      { buffer = buf, desc = "Ask the Agent to Edit Task" })
  end)
end

-- After a save that changed the title: rename the file, then point the buffer, its draft info
-- and any workspace at the new name. The buffer keeps its undo history.
function M.follow_rename(buf, target)
  local name, old = tasks.rename(target)
  if not old then return end
  target.task_file = name
  local info = vim.b[buf].taskbay_task
  if info then
    info.target.task_file = name
    vim.b[buf].taskbay_task = info
  end
  for _, workspace in pairs(core.workspaces) do
    if identity(workspace) == identity(target) then
      workspace.task_file = name
      core.save(workspace)
    end
  end
  local path = tasks.file(target)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.b[buf].taskbay_renaming = true
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent keepalt file " .. vim.fn.fnameescape(path))
      vim.cmd("silent write!") -- same content; clears the "not edited" state so plain :w keeps working
    end)
    vim.b[buf].taskbay_renaming = false
  end)
  vim.notify("Renamed task file to " .. name, vim.log.levels.INFO)
end

-- Field changes made in the Fields tab of a remote draft, compared against the
-- normalised issue snapshot, as the driver's update() changes; nil when the Fields
-- tab has not touched anything. A milestone of "" clears it.
function M.field_diffs(overlay, issue)
  if not overlay then return nil end
  issue = issue or {}
  local function changed(old_list, new_list)
    local old, present, add, remove = {}, {}, {}, {}
    for _, value in ipairs(old_list or {}) do old[value] = true end
    for _, value in ipairs(new_list or {}) do
      present[value] = true
      if not old[value] then add[#add + 1] = value end
    end
    for value in pairs(old) do if not present[value] then remove[#remove + 1] = value end end
    return add, remove
  end
  local add_labels, remove_labels = changed(issue.labels, overlay.labels)
  local add_assignees, remove_assignees = changed(issue.assignees, overlay.assignees)
  local milestone = (overlay.milestone or "") ~= (issue.milestone or "") and (overlay.milestone or "") or nil
  local state = (overlay.state or "open") ~= (issue.state or "open") and overlay.state or nil
  if #add_labels == 0 and #remove_labels == 0 and #add_assignees == 0 and #remove_assignees == 0
    and not milestone and not state then
    return nil
  end
  return { add_labels = add_labels, remove_labels = remove_labels,
    add_assignees = add_assignees, remove_assignees = remove_assignees, milestone = milestone, state = state }
end

-- Human summary of a field diff for the publish confirmation.
function M.field_changes(diffs)
  local changes = {}
  for _, label in ipairs(diffs.add_labels or {}) do changes[#changes + 1] = "+label " .. label end
  for _, label in ipairs(diffs.remove_labels or {}) do changes[#changes + 1] = "-label " .. label end
  for _, assignee in ipairs(diffs.add_assignees or {}) do changes[#changes + 1] = "+assignee " .. assignee end
  for _, assignee in ipairs(diffs.remove_assignees or {}) do changes[#changes + 1] = "-assignee " .. assignee end
  if diffs.milestone then changes[#changes + 1] = "milestone " .. (diffs.milestone == "" and "(none)" or diffs.milestone) end
  if diffs.state then changes[#changes + 1] = "state " .. diffs.state end
  return changes
end

function M.publish(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  core.task(function()
    assert(not publishing[buf], "Issue draft is already being published")
    publishing[buf] = true
    local ok, err = pcall(function()
      local info = draft(buf)
      assert(info.target.source ~= "local", "Local tasks save with :write; there is nothing to publish")
      -- Fields edited after this buffer was opened live in the baseline; pick
      -- them (and the current snapshot reference) up before diffing.
      local path, baseline = paths(info.target)
      if vim.uv.fs_stat(baseline) then
        local fresh = core.read_json(baseline)
        info.issue, info.fields = fresh.issue or info.issue, fresh.fields
      end
      M.save(buf)
      local task = tasks.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      local title, body = task.title, task.body
      local diffs = M.field_diffs(info.fields, info.issue)
      local action = diffs and "Publish title, body and fields" or "Publish title and body"
      local saved = read(path)
      if core.choose({ "Cancel", action },
        "Publish this draft to " .. identity(info.target) .. "?"
          .. (diffs and ("\nFields: " .. table.concat(M.field_changes(diffs), ", ")) or "")) ~= action then return end
      local current = fetch(info.target)
      assert(current.title == info.title and (current.body or "") == info.body,
        "Issue changed on " .. tasks.driver(info.target).title
          .. "; publishing was blocked. Review it and use :TaskbayReload before retrying")
      assert(vim.api.nvim_buf_is_valid(buf) and not vim.bo[buf].modified and read(path) == saved,
        "Draft changed during confirmation; review it and publish again")
      tasks.update(info.target, title, body, diffs)
      info.title, info.body = title, body
      info.fields = nil -- pushed; the next Fields edit starts from the current issue
      core.write(baseline, vim.json.encode(info))
      if vim.api.nvim_buf_is_valid(buf) then vim.b[buf].taskbay_task = info end
      refresh(info.target, title)
      vim.notify("Published " .. identity(info.target), vim.log.levels.INFO)
    end)
    publishing[buf] = nil
    if not ok then error(err, 0) end
  end)
end

function M.agent(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  core.task(function()
    local info = draft(buf)
    local workspace = core.current()
    if not (workspace and identity(workspace) == identity(info.target)) then
      local started = vim.iter(vim.tbl_values(core.workspaces))
        :any(function(other) return identity(other) == identity(info.target) end)
      error(started and "Switch to this task's tab first (Enter in " .. core.key("panel") .. ")" or "Start this task from " .. core.key("panel") .. " first", 0)
    end
    local job = core.jobs[workspace.id]
    assert(job and not job.exited, "Start this task's agent with " .. core.key("agent") .. " first")
    local request = core.input("How should the agent revise this task? ", "")
    if not request or vim.trim(request) == "" then
      return vim.notify("No revision request entered; nothing was sent to the agent", vim.log.levels.WARN,
        { title = "Taskbay" })
    end
    draft(buf)
    assert(core.jobs[workspace.id] == job and not job.exited, "The task's agent stopped; no request was sent")
    M.save(buf)
    local path = paths(info.target)
    local prompt = (info.target.source == "local" and "Edit only the local task file at "
      or "Edit only the local issue draft at ") .. vim.json.encode(path)
      .. " for " .. identity(info.target) .. ". The first line is a '# Title' heading, followed by a blank line "
      .. "and the Markdown task body. Read the existing file first. Do not publish the issue, "
      .. "run issue tracker commands (gh, glab, ...), change other repository files, or delegate this task. "
      .. "Leave the revised draft for human review in Neovim.\nRequested revision:\n" .. request
    core.paste(workspace, prompt)
    core.show(workspace)
    vim.notify("Draft revision pasted into the agent; press Enter there to submit", vim.log.levels.INFO)
  end)
end

function M.compose(repo, on_created)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "acwrite", "hide", false
  vim.bo[buf].filetype = "markdown"
  local name = "task://new/" .. buf
  vim.api.nvim_buf_set_name(buf, name)
  -- New tasks start with an Actions checklist: the agent works through and keeps it current.
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# ", "", "## Actions", "", "- [ ] " })
  vim.api.nvim_win_set_buf(0, buf)
  vim.wo.winbar = " \u{f0f6} New task  ·  # title, then the body  ·  :write creates it  ·  " .. core.key("panel") .. " starts it "
  local write
  write = vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function(event)
      core.task(function()
        if event.match ~= name then
          vim.api.nvim_buf_set_name(buf, name)
          error("Use :write without a filename; the task filename is allocated automatically")
        end
        local task = tasks.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        local target = tasks.create(repo, task.title, task.body)
        vim.api.nvim_del_autocmd(write)
        vim.bo[buf].buftype = ""
        vim.api.nvim_buf_set_name(buf, tasks.file(target))
        vim.api.nvim_buf_call(buf, function() vim.cmd("silent edit!") end)
        M.open(target)
        vim.notify("Created " .. tasks.label(target), vim.log.levels.INFO)
        require("taskbay.ui").task_created(target)
        if on_created then on_created(target) end
      end)
    end,
  })
  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  vim.schedule(function()
    if vim.api.nvim_get_current_buf() == buf then vim.cmd("startinsert!") end
  end)
end

return M
