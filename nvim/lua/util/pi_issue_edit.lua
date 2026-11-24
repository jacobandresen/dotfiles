local M = {}
local core = require("util.pi_issues")
local tasks = require("util.pi_tasks")
local fields = require("util.pi_issue_fields")
local publishing = {}

local identity, fetch = tasks.identity, tasks.get

local function paths(target)
  if target.source == "local" then return tasks.file(target) end
  local id = vim.fn.sha256(identity(target))
  local directory = core.settings().state_dir .. "/issue-drafts/" .. id
  return directory .. "/issue.md", directory .. "/baseline.json"
end
M.paths = paths -- also used by the Fields tab for GitHub draft baselines

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

local function draft(buf)
  assert(vim.api.nvim_buf_is_valid(buf), "Task buffer was closed")
  local info = vim.b[buf].pi_issue_draft
  assert(info, "Open a task with :PiTaskView first")
  return info
end

function M.open(target, reload, edit_with_pi)
  target = target or core.current()
  if not target then
    return vim.notify("Choose a task with Space a i first", vim.log.levels.WARN)
  end
  core.task(function()
    local path, baseline = paths(target)
    local local_task = target.source == "local"
    local previous = vim.uv.fs_stat(path) and read(path)
    local buf = vim.fn.bufnr(path)
    local tick = buf >= 0 and vim.api.nvim_buf_get_changedtick(buf)
    if reload and core.choose({ "Cancel", "Replace local draft" },
      "Discard buffer edits and reload " .. identity(target)
        .. (local_task and " from disk?" or " from GitHub?")) ~= "Replace local draft" then
      return
    end
    if not local_task and (reload or not vim.uv.fs_stat(path)) then
      local issue = fetch(target)
      assert(buf < 0 or vim.api.nvim_buf_get_changedtick(buf) == tick,
        "Draft changed while fetching; no local edits were replaced")
      assert((vim.uv.fs_stat(path) and read(path)) == previous,
        "Draft changed on disk while fetching; no local edits were replaced")
      core.write(path, "# " .. issue.title .. "\n\n" .. (issue.body or "") .. "\n")
      -- The full issue snapshot (labels, assignees, milestone, comments, ...)
      -- stays in the local baseline: editing or publishing the draft never
      -- drops information from the original GitHub issue.
      core.write(baseline, vim.json.encode(
        { target = target, title = issue.title, body = issue.body or "", url = issue.url, issue = issue }))
      if buf >= 0 and vim.api.nvim_buf_is_loaded(buf) then
        vim.api.nvim_buf_call(buf, function() vim.cmd("silent edit!") end)
      end
    end
    local info
    if local_task then
      fetch(target)
      if reload and buf >= 0 and vim.api.nvim_buf_is_loaded(buf) then
        vim.api.nvim_buf_call(buf, function() vim.cmd("silent edit!") end)
      end
      info = { target = target }
    else
      assert(vim.uv.fs_stat(baseline), "Draft baseline is missing; use :PiTaskReload to reload explicitly")
      info = vim.json.decode(read(baseline))
    end
    assert(identity(info.target) == identity(target), "Task identity does not match")
    info.target = target
    buf = vim.fn.bufadd(path)
    vim.fn.bufload(buf)
    vim.b[buf].pi_issue_draft = info
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
        and "\u{f0f6} Task | :write save | Tab fields | Space ag start | Space aR restart | Space ae ask Pi "
      or "\u{f09b} GitHub draft | :write save locally | Tab fields | Space aP publish | Space ae Pi "
    fields.decorate(buf, target)
    if local_task then
      vim.api.nvim_create_autocmd("BufWritePost", {
        group = vim.api.nvim_create_augroup("pi_local_task_" .. buf, { clear = true }),
        buffer = buf,
        callback = function()
          if vim.b[buf].pi_task_renaming then return end
          core.task(function()
            M.follow_rename(buf, target)
            refresh(target, fetch(target).title)
            fields.decorate(buf, target)
            for _, workspace in pairs(core.workspaces) do
              if workspace.started and identity(workspace) == identity(target) then
                vim.notify("Task updated. Space a R restarts " .. tasks.label(workspace)
                  .. " with it; resuming with p sends it to the current conversation.", vim.log.levels.INFO)
              end
            end
          end)
        end,
      })
    else
      vim.keymap.set("n", "<leader>aP", function() M.publish(buf) end,
        { buffer = buf, desc = "Publish Issue Draft (Confirm)" })
    end
    -- Tab and Space af both flip to the Fields tab; Tab flips back.
    vim.keymap.set("n", "<Tab>", function() fields.open(target) end,
      { buffer = buf, nowait = true, desc = "Fields Tab" })
    vim.keymap.set("n", "<leader>af", function() fields.open(target) end,
      { buffer = buf, desc = "Fields Tab (Confirm)" })
    vim.keymap.set("n", "<leader>ae", function() M.agent(buf) end,
      { buffer = buf, desc = "Ask Pi to Edit Task" })
    if edit_with_pi then M.agent(buf) end
  end)
end

-- After a save that changed the title: rename the file, then point the buffer, its draft info
-- and any workspace at the new name. The buffer keeps its undo history.
function M.follow_rename(buf, target)
  local name, old = tasks.rename(target)
  if not old then return end
  target.task_file = name
  local info = vim.b[buf].pi_issue_draft
  if info then
    info.target.task_file = name
    vim.b[buf].pi_issue_draft = info
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
    vim.b[buf].pi_task_renaming = true
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent keepalt file " .. vim.fn.fnameescape(path))
      vim.cmd("silent write!") -- same content; clears the "not edited" state so plain :w keeps working
    end)
    vim.b[buf].pi_task_renaming = false
  end)
  vim.notify("Renamed task file to " .. name, vim.log.levels.INFO)
end

-- Field changes made in the Fields tab of a GitHub draft, as gh issue edit
-- flags. Compared against the original issue snapshot; nothing is re-sent when
-- the Fields tab has not touched them.
function M.field_diffs(overlay, issue)
  if not overlay then return nil end
  issue = issue or {}
  local names_of = function(list, key) return vim.tbl_map(function(e) return e[key] or tostring(e) end, list or {}) end
  local function changed(old_list, new_list, key)
    local old, present, add, remove = {}, {}, {}, {}
    for _, value in ipairs(names_of(old_list, key)) do old[value] = true end
    for _, value in ipairs(new_list or {}) do
      present[value] = true
      if not old[value] then add[#add + 1] = value end
    end
    for value in pairs(old) do if not present[value] then remove[#remove + 1] = value end end
    return add, remove
  end
  local add_labels, remove_labels = changed(issue.labels, overlay.labels, "name")
  local add_assignees, remove_assignees = changed(issue.assignees, overlay.assignees, "login")
  local milestone = (overlay.milestone or "") ~= ((issue.milestone or {}).title or "")
    and (overlay.milestone ~= "" and overlay.milestone or "-") or nil
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
  if diffs.milestone then changes[#changes + 1] = "milestone " .. diffs.milestone end
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
      assert(info.target.source ~= "local", "Local tasks save with :write; there is nothing to publish to GitHub")
      -- Fields edited after this buffer was opened live in the baseline; pick
      -- them (and the current snapshot reference) up before diffing.
      local path, baseline = paths(info.target)
      if vim.uv.fs_stat(baseline) then
        local fresh = vim.json.decode(read(baseline))
        info.issue, info.fields = fresh.issue or info.issue, fresh.fields
      end
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("checktime")
        vim.cmd("silent update")
      end)
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
        "Issue changed on GitHub; publishing was blocked. Review it and use :PiTaskReload before retrying")
      assert(vim.api.nvim_buf_is_valid(buf) and not vim.bo[buf].modified and read(path) == saved,
        "Draft changed during confirmation; review it and publish again")
      tasks.update(info.target, title, body, diffs)
      info.title, info.body = title, body
      info.fields = nil -- pushed; the next Fields edit starts from the current issue
      core.write(baseline, vim.json.encode(info))
      if vim.api.nvim_buf_is_valid(buf) then vim.b[buf].pi_issue_draft = info end
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
    assert(workspace and identity(workspace) == identity(info.target),
      "Switch to this task's workspace (Space a w); prepare it from Space a i if needed")
    local job = core.jobs[workspace.id]
    assert(job and not job.exited, "Start this task's pi with Space a p first")
    local request = core.input("How should pi revise this task? ", "")
    if not request or vim.trim(request) == "" then
      return vim.notify("No revision request entered; nothing was sent to pi", vim.log.levels.WARN,
        { title = "Pi Tasks" })
    end
    draft(buf)
    assert(core.jobs[workspace.id] == job and not job.exited, "The task's pi session stopped; no request was sent")
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("checktime")
      vim.cmd("silent update")
    end)
    local path = paths(info.target)
    local prompt = (info.target.source == "local" and "Edit only the local task file at "
      or "Edit only the local GitHub issue draft at ") .. vim.json.encode(path)
      .. " for " .. identity(info.target) .. ". The first line is a '# Title' heading, followed by a blank line "
      .. "and the Markdown task body. Read the existing file first. Do not publish to GitHub, "
      .. "run gh issue edit, change other repository files, or delegate this task. "
      .. "Leave the revised draft for human review in Neovim.\nRequested revision:\n" .. request
    core.paste(workspace, prompt)
    core.show(workspace)
    vim.notify("Draft revision pasted into pi; press Enter there to submit", vim.log.levels.INFO)
  end)
end

function M.edit()
  if vim.b.pi_issue_draft then M.agent() else M.open(nil, false, true) end
end

function M.compose(repo)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "acwrite", "hide", false
  vim.bo[buf].filetype = "markdown"
  local name = "task://new/" .. buf
  vim.api.nvim_buf_set_name(buf, name)
  -- New tasks start with an Actions checklist: the agent works through and keeps it current.
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# ", "", "## Actions", "", "- [ ] " })
  vim.api.nvim_win_set_buf(0, buf)
  vim.wo.winbar = " \u{f0f6} New local task | Write a title and body | :write creates it | then Space ag starts it "
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
      end)
    end,
  })
  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  vim.schedule(function()
    if vim.api.nvim_get_current_buf() == buf then vim.cmd("startinsert!") end
  end)
end

return M
