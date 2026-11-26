-- The issue tracker flows: import issues as local tasks (picker, by number, or the open
-- remote workspace) and export a local task as a new issue. Drivers do the tracker work.
local M = {}
local core = require("taskbay.core")
local tasks = require("taskbay.store")

-- The only remaining picker: importing remote issues copies them into local
-- tasks (never starts one). Working on an issue happens only from the
-- workspace panel, where the imported task becomes a selectable row.
function M.import_picker(repository, query, limit)
  if not core.require_remote() then return end
  local root = repository and repository.root or core.root()
  limit = limit or 50
  core.task(function()
    local repo = repository or core.repository(root, core.settings().remote)
    local remote = tasks.driver(repo)
    local items = tasks.list(repo, query, limit)
    for _, issue in ipairs(items) do
      local labels = issue.labels or {}
      issue.text = remote.glyph .. " " .. ("%d %s"):format(issue.number, core.clean(issue.title))
        .. (#labels > 0 and ("  [" .. table.concat(labels, ", ") .. "]") or "")
        .. (issue.state == "closed" and "  (closed)" or "")
    end
    local title = repo.repo .. " / Import " .. remote.title .. " Issues"
    if #items == 0 then
      title = (query and query ~= "" and "No matching open issues / " or "No open issues / ") .. repo.repo
    end
    -- Ctrl-o / Ctrl-f open the issue under the cursor as a draft / its Fields; nothing starts.
    local function open_issue(picker, open)
      local issue = picker:current()
      if not issue then return end
      picker:close()
      open({
        host = repo.host, repo = repo.repo, number = issue.number, path = repo.root,
        source = repo.source, task_root = repo.task_root, task_file = issue.task_file,
      })
    end
    Snacks.picker({
      title = title,
      items = items,
      show_empty = true,
      format = "text",
      layout = {
        preset = "select",
        layout = {
          footer = "Enter import  Tab select  C-o view  C-f fields  C-s search  C-l more",
          footer_pos = "center",
        },
      },
      confirm = function(picker)
        local selected = picker:selected({ fallback = true })
        picker:close()
        if #selected == 0 then return end
        M.import_issues(repo, selected)
      end,
      actions = {
        view_issue = function(picker) open_issue(picker, require("taskbay.editor").open) end,
        view_fields = function(picker) open_issue(picker, require("taskbay.fields").open) end,
        server_search = function(picker)
          picker:close()
          core.task(function()
            local search = core.input(remote.title .. " issue search: ", query or "")
            if search then M.import_picker(repo, search, limit) end
          end)
        end,
        more_issues = function(picker)
          picker:close()
          M.import_picker(repo, query, limit + 50)
        end,
      },
      win = {
        input = {
          keys = {
            ["<C-s>"] = { "server_search", mode = { "n", "i" } },
            ["<C-l>"] = { "more_issues", mode = { "n", "i" } },
            ["<C-o>"] = { "view_issue", mode = { "n", "i" } },
            ["<C-f>"] = { "view_fields", mode = { "n", "i" } },
          },
        },
      },
    })
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

-- Copy remote issues into the local .tasks store after confirmation. The tracker's
-- own issue data goes verbatim into the sidecar, so nothing from the original is dropped.
local function import_now(repo, items)
  local root = repo.root or (items[1] and items[1].path) or core.root()
  local local_repo = core.repository(root, "local")
  local fetched = {}
  for _, item in ipairs(items) do
    fetched[#fetched + 1] = { number = item.number, issue = tasks.get({
      source = repo.source, repo = repo.repo, host = repo.host, number = item.number, path = root,
    }) }
  end
  local what = #fetched == 1
      and ("%s issue #%d in %s?"):format(tasks.driver(repo).title, fetched[1].number, repo.repo)
    or (#fetched .. " issues in " .. repo.repo .. "?")
  if core.choose({ "Cancel", "Import as local task" },
    "Copy " .. what .. " into " .. local_repo.root .. "/.tasks/?") ~= "Import as local task" then return end
  local last
  for _, entry in ipairs(fetched) do
    local issue = entry.issue
    local imported = tasks.create(local_repo, issue.title, issue.body)
    tasks.set_meta(imported, {
      origin = tasks.identity({ source = repo.source, repo = repo.repo, host = repo.host, number = entry.number }),
      labels = issue.labels, assignees = issue.assignees, milestone = issue.milestone, state = issue.state,
      relations = {},
      details = { author = issue.author, created_at = issue.created_at, updated_at = issue.updated_at,
        closed_at = issue.closed_at, comments = issue.comments },
      issue = issue.raw, -- the tracker's verbatim data; the fields above are editable views
    })
    last = imported
  end
  if last then require("taskbay.editor").open(last) end
  vim.notify(("Imported %d issue(s) as local task(s); the original issue data (labels, comments, ...) "
    .. "is kept in each task's metadata"):format(#fetched), vim.log.levels.INFO, { title = "Taskbay" })
end

function M.import_issues(repo, items)
  return copy_task(function() import_now(repo, items) end)
end

-- Import by number (:TaskbayImport 42, or from an open remote issue workspace); without
-- one, pick from the repository's open issues instead.
function M.import_task(number)
  local current = core.current()
  local root = core.root()
  if not core.require_remote() then return end
  if not number and current and current.source ~= "local" then
    return copy_task(function()
      import_now({ source = current.source, repo = current.repo, host = current.host }, { current })
    end)
  end
  if number then
    assert(tostring(number):match("^%d+$") and tonumber(number) > 0, "Enter a positive issue number")
    return copy_task(function()
      import_now(core.repository(root, core.settings().remote), { { number = tonumber(number) } })
    end)
  end
  return M.import_picker()
end

function M.export_task(target)
  if not core.require_remote() then return end
  local info = vim.b.taskbay_task
  target = target or (info and info.target) or core.current()
  return copy_task(function()
    assert(target and target.source == "local", "Open a local task or activate its workspace before exporting")
    local repo = core.repository(target.task_root, core.settings().remote)
    local path = tasks.file(target)
    local buf = vim.fn.bufnr(path)
    if buf >= 0 and vim.api.nvim_buf_is_loaded(buf) then require("taskbay.editor").save(buf) end
    local task = tasks.get(target)
    local action = "Create " .. core.remote().title .. " issue"
    if core.choose({ "Cancel", action },
      "Publish " .. tasks.label(target) .. " as a NEW issue in " .. repo.host .. "/" .. repo.repo .. "?")
      ~= action then return end
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

return M
