-- The Fields tab is the advanced half of a task. The Task buffer shows the
-- minimal view (title, Markdown body, relations); Fields edits labels,
-- assignees, milestone, state and relations and shows read-only issue data.
-- Local tasks store everything in the '.tasks/NNN.json' sidecar; remote drafts
-- overlay edits onto the baseline snapshot, so nothing from the original issue
-- is ever dropped or mutated. Issues arrive normalised by their driver (taskbay/remotes).
local M = {}
local core = require("taskbay.core")
local tasks = require("taskbay.store")

local KINDS = { "relates", "blocks", "blocked_by", "duplicate_of" }
local KIND_TEXT = { relates = "relates", blocks = "blocks", blocked_by = "blocked by", duplicate_of = "duplicate of" }
local KIND_OF = { relates = "relates", blocks = "blocks", ["blocked-by"] = "blocked_by", ["duplicate-of"] = "duplicate_of" }
local STATE = { open = true, closed = true, [""] = true }

local function editor() return require("taskbay.editor") end
local identity = tasks.identity

-- Read-only issue data shown below the editable fields (a normalised issue's details).
local function readonly(origin, issue)
  return { origin = origin, author = issue.author, created_at = issue.created_at, updated_at = issue.updated_at,
    closed_at = issue.closed_at, comments = issue.comments }
end

-- Task buffers (Task tab) showing this target.
local function task_bufs(target)
  return vim.tbl_filter(function(buf)
    local draft = vim.b[buf].taskbay_task
    return draft and draft.target and identity(draft.target) == identity(target) or false
  end, vim.api.nvim_list_bufs())
end
local ns = vim.api.nvim_create_namespace("taskbay_relations")

-- Normalised, editable view of a target's issue data. `write(values)` persists
-- the edited fields; everything outside the editable keys keeps its storage.
function M.fields(target)
  local fields = {
    labels = {}, assignees = {}, milestone = nil, state = "open", relations = {},
    readonly = {}, write = nil,
  }
  if target.source == "local" then
    local meta = tasks.get_meta(target)
    fields.labels = meta.labels or {}
    fields.assignees = meta.assignees or {}
    fields.milestone = meta.milestone
    fields.state = (meta.state or "open"):lower() -- tasks imported before state was normalised hold OPEN
    fields.relations = meta.relations or {}
    -- Imports from before the tracker drivers kept only GitHub's raw issue; read details from it.
    local details = meta.details or (meta.issue and tasks.remote("github").normalise(meta.issue)) or {}
    fields.readonly = readonly(meta.origin, details)
    fields.write = function(values)
      local raw = tasks.get_meta(target) -- keep the snapshot and any custom keys
      raw.labels, raw.assignees, raw.milestone, raw.state, raw.relations =
        values.labels, values.assignees, values.milestone, values.state, values.relations
      tasks.set_meta(target, raw)
    end
    return fields
  end
  local _, baseline_path = editor().paths(target)
  local base = core.read_json(baseline_path)
  local issue = base.issue or {}
  -- Saved Fields replace the issue's values as a whole (a cleared milestone stays cleared).
  local saved = base.fields or issue
  fields.labels, fields.assignees, fields.milestone = saved.labels or {}, saved.assignees or {}, saved.milestone
  fields.state, fields.relations = saved.state or "open", saved.relations or {}
  fields.readonly = readonly(identity(target), issue)
  fields.write = function(values)
    base = core.read_json(baseline_path)
    base.fields = { labels = values.labels, assignees = values.assignees,
      milestone = values.milestone, state = values.state, relations = values.relations }
    core.write(baseline_path, vim.json.encode(base))
  end
  return fields
end

-- Editable section (one 'key: values' line per field), then a read-only
-- section. The write handler parses only the editable top part; anything below
-- the read-only marker is decoration.
function M.render(target, fields)
  local by_kind = {}
  for _, kind in ipairs(KINDS) do by_kind[kind] = {} end
  for _, relation in ipairs(fields.relations or {}) do
    if not KIND_TEXT[relation.kind] then error("Unknown relation kind: " .. tostring(relation.kind)) end
    table.insert(by_kind[relation.kind], relation.target)
  end
  local lines = { "# Fields — " .. tasks.label(target), "" }
  local function line(key, values)
    lines[#lines + 1] = key .. ": " .. table.concat(vim.tbl_map(tostring, values or {}), ", ")
  end
  line("labels", fields.labels)
  line("assignees", fields.assignees)
  line("milestone", { fields.milestone })
  line("state", { fields.state or "open" })
  for _, kind in ipairs(KINDS) do
    local key = kind == "blocked_by" and "blocked-by" or kind == "duplicate_of" and "duplicate-of" or kind
    line(key, by_kind[kind])
  end
  lines[#lines + 1] = "---  read only"
  for _, key in ipairs({ "origin", "author", "created_at", "updated_at", "closed_at", "comments" }) do
    local value = fields.readonly[key]
    if value then lines[#lines + 1] = key .. ": " .. tostring(value) end
  end
  return lines
end

local function split_values(text)
  local values = {}
  for value in vim.gsplit(text, ",", { plain = true }) do
    value = vim.trim(value)
    if value ~= "" then values[#values + 1] = value end
  end
  return values
end

-- Parse edited buffer lines back into a values table. Each relation belongs to
-- the 'kind:' line it was written under.
function M.values(lines)
  local values = { labels = {}, assignees = {}, milestone = nil, state = "open", relations = {} }
  for _, raw in ipairs(lines) do
    local line = vim.trim(raw)
    if line:match("^%-%-%-") then break end
    if line ~= "" and not line:match("^%s*#") then
      local key, rest = line:match("^([%a%-_]+)%s*:%s*(.*)$")
      if not key then
        error("Fields lines look like 'key: values' — fix or delete: " .. line)
      end
      rest = vim.trim(rest)
      if key == "labels" then
        values.labels = split_values(rest)
      elseif key == "assignees" then
        values.assignees = split_values(rest)
      elseif key == "milestone" then
        values.milestone = rest ~= "" and rest or nil
      elseif key == "state" then
        assert(STATE[rest] ~= nil, "state must be open or closed")
        values.state = rest ~= "" and rest or "open"
      elseif KIND_OF[key] then
        for _, text in ipairs(split_values(rest)) do
          values.relations[#values.relations + 1] = { kind = KIND_OF[key], target = text }
        end
      else
        error("Unknown editable field: " .. key)
      end
    end
  end
  return values
end

-- Relations shown as virtual lines under the body in the Task buffer.
function M.decorate(buf, target)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local lines = {}
  for _, relation in ipairs(M.fields(target).relations or {}) do
    lines[#lines + 1] = { { "" },
      { (relation.kind == "relates" and "↳ relates to " or "↳ " .. KIND_TEXT[relation.kind] .. " ")
        .. relation.target, "Comment" } }
  end
  if #lines == 0 then return end
  vim.api.nvim_buf_set_extmark(buf, ns, vim.api.nvim_buf_line_count(buf) - 1, 0, {
    virt_lines = lines, strict = false,
  })
end

function M.open(target)
  target = target or core.current()
  if not target then return vim.notify("Choose a task in " .. core.key("panel") .. " first", vim.log.levels.WARN) end
  if target.source ~= "local" then
    -- A remote draft's fields live on its baseline; make sure it exists first.
    local _, baseline = editor().paths(target)
    if not vim.uv.fs_stat(baseline) then
      return vim.notify("Open the issue first (Ctrl-o in the import picker); its Fields tab follows then", vim.log.levels.INFO)
    end
  end
  core.task(function()
    local fields = M.fields(target)
    local lines = M.render(target, fields)
    local name = "task://fields/" .. vim.fn.sha256(identity(target))
    local buf = vim.fn.bufnr(name)
    if buf < 0 then
      buf = vim.api.nvim_create_buf(true, false)
      vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "acwrite", "hide", false
      vim.api.nvim_buf_set_name(buf, name)
      vim.b[buf].taskbay_fields_for = identity(target)
      vim.api.nvim_create_autocmd("BufWriteCmd", {
        buffer = buf,
        callback = function()
          core.task(function()
            -- Parse the editable section, then persist through the write path
            -- captured at render, which re-reads storage (external edits are
            -- never overwritten; snapshots stay verbatim).
            local values = M.values(vim.api.nvim_buf_get_lines(buf, 1, -1, false))
            fields.write(values)
            vim.bo[buf].modified = false
            vim.notify("Saved fields for " .. tasks.label(target), vim.log.levels.INFO)
            for _, probe in ipairs(task_bufs(target)) do M.decorate(probe, target) end
            for _, workspace in pairs(core.workspaces) do
              if identity(workspace) == identity(target) then core.changed() end
            end
          end)
        end,
      })
    end
    -- Fresh render on every open; the write path re-reads storage, so external
    -- edits are never overwritten by a stale buffer.
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modified = false
    vim.bo[buf].filetype = "text"
    vim.api.nvim_set_current_buf(buf)
    -- Tab flips back to the Task tab, matching Tab in the Task tab; q also returns.
    vim.wo.winbar = " \u{f02c} Fields  ·  :write save  ·  Tab task  ·  q back "
    vim.keymap.set("n", "q", function() M.close(target) end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<Tab>", function() M.close(target) end, { buffer = buf, nowait = true, desc = "Task Tab" })
  end)
end

-- Return from Fields to the task's own buffer (opening it through the editor's
-- normal flow when it is not already loaded).
function M.close(target)
  target = target or core.current()
  assert(target, "Return to a task with the Task/Fields tabs open")
  local buf = task_bufs(target)[1]
  if buf then return vim.api.nvim_set_current_buf(buf) end
  editor().open(target)
end

return M
