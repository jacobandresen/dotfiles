local M = {}
local providers = {}

local function core() return require("taskbay.core") end
-- A target's source is "local" (the .tasks store) or the name of a remote driver
-- (taskbay/remotes/<name>.lua). Workspaces saved before sources existed were GitHub issues.
local function source(target)
  local kind = target.source == nil and "github" or target.source
  assert(type(kind) == "string" and kind:match("^[%w_]+$"), "Unknown task source: " .. tostring(kind))
  return kind
end
local function valid_id(id)
  return type(id) == "number" and id > 0 and id <= 9007199254740991 and id % 1 == 0
end
M.valid_id = valid_id
-- A task file: '# Title', a blank line, the Markdown body.
function M.text(title, body) return "# " .. title .. "\n\n" .. (body or "") .. "\n" end
local function check_title(title)
  assert(type(title) == "string" and vim.trim(title) ~= "" and not title:find("[\r\n]"),
    "Enter a single-line task title")
end
local function slug(title)
  local value = title:lower():gsub("[^a-z0-9]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""):sub(1, 60)
  return value == "" and "task" or value
end
local function id(target)
  assert(valid_id(target.number), "Task ID must be a positive safe integer")
  return ("%.0f"):format(target.number)
end
-- Short display name derived from the title ("2-fix-kitty-clip"); nil without a
-- title or a valid ID (invalid IDs keep failing loudly at their call sites).
function M.name(target, width)
  if not valid_id(target.number) then return nil end
  local title = vim.trim(target.title or "")
  if title == "" then return nil end
  return tostring(target.number) .. "-" .. slug(title):sub(1, width or 24):gsub("%-+$", "")
end
function M.remote(name)
  if not providers[name] then
    local ok, driver = pcall(require, "taskbay.remotes." .. name)
    assert(ok and type(driver) == "table", "Unknown task source: " .. name)
    providers[name] = driver
  end
  return providers[name]
end
local function provider(target) return M.remote(source(target)) end
M.driver = provider -- the driver behind a target (local store or remote tracker)

function M.identity(target)
  if source(target) == "local" then
    return "local:" .. assert(target.task_root or target.root, "Local task repository is missing") .. "#" .. id(target)
  end
  return target.host .. "/" .. target.repo .. "#" .. id(target)
end
function M.label(target)
  local kind = source(target)
  local name = M.name(target)
  if name then
    return kind == "local" and (target.repo .. "/" .. name) or (target.repo .. "#" .. name)
  end
  return target.repo .. (kind == "local" and "/task-" or "#") .. id(target)
end
function M.branch(target)
  return (source(target) == "local" and "task/" or "issue/") .. id(target)
end
function M.worktree(repo, number)
  return vim.fs.dirname(repo.root) .. "/" .. vim.fs.basename(repo.root) .. "-worktrees/"
    .. (source(repo) == "local" and "task-" or "") .. id({ number = number })
end

-- The Git side of a repository: its primary checkout and common Git directory.
function M.checkout(root)
  local common = core().real(vim.trim(core().git(root, "rev-parse", "--path-format=absolute", "--git-common-dir")))
  local primary = core().worktrees(root)[1]
  assert(primary and primary.path, "No primary Git worktree")
  return { root = primary.path, common = common }
end


local function task_directory(target)
  local root = assert(target.task_root or target.root, "Local task repository is missing")
  local directory = root .. "/.tasks"
  assert(core().inside(directory, root), "Local task directory must stay inside its repository")
  return directory
end

local function number(name)
  local digits = name:match("^(%d+)[%w_.-]*%.md$")
  if not digits then return end
  local value = tonumber(digits)
  assert(valid_id(value), "Invalid task ID in " .. name)
  return value
end

local function task_files(target)
  local directory, files, seen, sidecars = task_directory(target), {}, {}, {}
  if not vim.uv.fs_stat(directory) then return files end
  for name, kind in vim.fs.dir(directory) do
    local id = number(name)
    if id and (kind == "file" or kind == "link") then
      assert(id > 0 and not seen[id], "Invalid or duplicate local task ID: " .. name)
      seen[id] = true
      files[#files + 1] = { number = id, task_file = name }
    elseif name:match("^(%d+)%.json$") then
      sidecars[tonumber(name:match("^(%d+)"))] = name
    end
  end
  -- A metadata sidecar without its Markdown file means the task was mangled.
  for id, name in pairs(sidecars) do
    assert(seen[id], "Task metadata " .. name .. " has no 'NNN-...' Markdown file")
  end
  return files
end

function M.file(target)
  assert(source(target) == "local", "Only local tasks have a source file")
  id(target)
  local name = target.task_file
  -- A remembered filename goes stale when the title (and so the file) is renamed.
  local stale = name and not name:find("/", 1, true) and number(name) == target.number
    and not vim.uv.fs_lstat(task_directory(target) .. "/" .. name)
  if not name or stale then
    name = nil
    for _, item in ipairs(task_files(target)) do
      if item.number == target.number then name = item.task_file end
    end
  end
  assert(type(name) == "string" and number(name) == target.number, "Local task file does not match its ID")
  local path = task_directory(target) .. "/" .. name
  assert(core().inside(path, task_directory(target)), "Local task files must stay inside .tasks")
  return path
end

providers["local"] = {
  repository = function(root)
    local repo = M.checkout(root)
    repo.source, repo.task_root, repo.host, repo.repo = "local", repo.root, "local", vim.fs.basename(repo.root)
    return repo
  end,
  get = function(target)
    local path = M.file(target)
    local task = M.parse(vim.fn.readfile(path))
    task.url, task.task_file, task.meta = path, vim.fs.basename(path), M.get_meta(target)
    return task
  end,
  list = function(repo, query, limit)
    local items = {}
    for _, item in ipairs(task_files(repo)) do
      item.source, item.task_root, item.repo, item.host = "local", repo.root, repo.repo, "local"
      local task = providers["local"].get(item)
      item.title, item.url, item.meta, item.actions = task.title, task.url, task.meta, M.actions(task)
      if not query or query == "" or (task.title .. "\n" .. task.body):lower():find(query:lower(), 1, true) then
        items[#items + 1] = item
        if #items >= limit then break end
      end
    end
    return items
  end,
  update = function(target, title, body)
    core().write(M.file(target), M.text(title, body))
    target.task_file = M.rename(target)
  end,
  create = function(repo, title, body)
    local directory = task_directory(repo)
    vim.fn.mkdir(directory, "p")
    local lock_path = directory .. "/.create.lock"
    local lock = assert(vim.uv.fs_open(lock_path, "wx", 384),
      "Task creation is locked; retry or inspect " .. lock_path)
    local ok, item = pcall(function()
      local files = task_files(repo)
      local id = #files > 0 and files[#files].number + 1 or 1
      local task = { source = "local", number = id, task_root = repo.root,
        task_file = ("%03d-%s.md"):format(id, slug(title)), title = title, repo = repo.repo, host = "local", path = repo.root }
      local path = directory .. "/" .. task.task_file
      assert(core().inside(path, directory), "Local task files must stay inside .tasks")
      local data = M.text(title, body)
      local fd, err = vim.uv.fs_open(path, "wx", 384)
      assert(fd, "Cannot create local task: " .. tostring(err))
      local written, write_err = vim.uv.fs_write(fd, data, 0)
      vim.uv.fs_close(fd)
      assert(written == #data, write_err or ("Incomplete task write: " .. path))
      return task
    end)
    vim.uv.fs_close(lock)
    assert(vim.uv.fs_unlink(lock_path))
    if not ok then error(item, 0) end
    return item
  end,
}

-- Keep the filename in step with the title: same number prefix, new slug.
-- Returns the (possibly new) filename and the old one when it changed.
function M.rename(target)
  local path = M.file(target)
  local old = vim.fs.basename(path)
  local task = M.parse(vim.fn.readfile(path))
  local name = old:match("^(%d+)") .. "-" .. slug(task.title) .. ".md"
  if name == old then return old end
  local destination = vim.fs.dirname(path) .. "/" .. name
  assert(not vim.uv.fs_lstat(destination), "Cannot rename task: " .. destination .. " already exists")
  assert(vim.uv.fs_rename(path, destination))
  return name, old
end

function M.parse(lines)
  local title = lines[1] and lines[1]:match("^# (.+)$")
  assert(title and vim.trim(title) ~= "" and not title:find("[\r\n]") and lines[2] == "",
    "Keep '# Title', then a blank line and the Markdown body")
  return { title = title, body = table.concat(lines, "\n", 3) }
end

-- Action list progress: counts '- [ ]' / '- [x]' checklist lines in the body.
-- Tasks should carry actionable items; the agent keeps the list current.
function M.actions(task)
  local total, done = 0, 0
  for _, line in ipairs(vim.split(task.body or "", "\n", { plain = true })) do
    if line:match("^%s*[-*] %[.%]") then
      total = total + 1
      if line:match("^%s*[-*] %[x%]") then done = done + 1 end
    end
  end
  return { done = done, total = total }
end

-- Task metadata: a '.tasks/NNN.json' sidecar next to the Markdown file. The
-- Markdown stays minimal (title, body, nothing else); the sidecar holds the
-- full snapshot of imported remote issues verbatim plus editable fields and
-- relations, and is itself a plain editable JSON file.
function M.meta_path(target)
  assert(source(target) == "local", "Only local tasks have a metadata sidecar")
  id(target)
  local path = M.file(target)
  local candidate = vim.fs.dirname(path) .. "/" .. ("%03d.json"):format(target.number)
  assert(core().inside(candidate, task_directory(target)), "Task metadata must stay inside .tasks")
  return candidate
end

function M.get_meta(target)
  local path = M.meta_path(target)
  if not vim.uv.fs_stat(path) then return {} end
  local ok, data = pcall(core().read_json, path)
  assert(ok and type(data) == "table", "Task metadata must be one JSON object: " .. path)
  return data
end

-- Written fields replace their previous values; every other key (an imported
-- snapshot, custom keys) is preserved untouched.
function M.set_meta(target, meta)
  assert(type(meta) == "table", "Task metadata must be a JSON object")
  local path = M.meta_path(target)
  if next(meta) == nil then
    if vim.uv.fs_stat(path) then assert(vim.uv.fs_unlink(path)) end
    return
  end
  core().write(path, vim.json.encode(meta) .. "\n")
end

local function enabled(target)
  assert(source(target) == "local" or core().settings().remote_enabled,
    "The issue tracker integration is disabled; set vim.g.taskbay.remote_enabled = true to enable it")
end

function M.repository(root, kind)
  local target = { source = kind == nil and "local" or kind }
  local driver = provider(target)
  enabled(target)
  local repo = driver.repository(root)
  repo.source = target.source
  return repo
end
function M.list(repo, query, limit)
  enabled(repo)
  return provider(repo).list(repo, query, limit or 50)
end
function M.get(target)
  enabled(target)
  return provider(target).get(target)
end
function M.update(target, title, body, extra)
  enabled(target)
  check_title(title)
  assert(type(body) == "string", "Task body must be Markdown text")
  return provider(target).update(target, title, body, extra)
end
function M.delete(target)
  assert(source(target) == "local", "Only local tasks can be deleted")
  -- Delete tolerates an already-missing Markdown file (stale dashboard row):
  -- resolve the sidecar from the ID, the Markdown only when it still exists.
  local directory = task_directory(target)
  local meta = directory .. "/" .. ("%03d.json"):format(id(target))
  assert(core().inside(meta, directory), "Task metadata must stay inside .tasks")
  local ok, path = pcall(M.file, target)
  if ok and vim.uv.fs_stat(path) then assert(vim.uv.fs_unlink(path)) end
  if vim.uv.fs_stat(meta) then assert(vim.uv.fs_unlink(meta)) end
end
function M.create(repo, title, body)
  enabled(repo)
  check_title(title)
  assert(body == nil or type(body) == "string", "Task body must be Markdown text")
  return provider(repo).create(repo, title, body)
end

return M
