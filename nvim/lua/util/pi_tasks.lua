local M = {}
local providers = {}

local function core() return require("util.pi_issues") end
local function source(target)
  local kind = target.source == nil and "github" or target.source
  assert(kind == "local" or kind == "github", "Unknown task source: " .. tostring(kind))
  return kind
end
local function valid_id(id)
  return type(id) == "number" and id > 0 and id <= 9007199254740991 and id % 1 == 0
end
local function id(target)
  assert(valid_id(target.number), "Task ID must be a positive safe integer")
  return ("%.0f"):format(target.number)
end
local function provider(target)
  return assert(providers[source(target)], "Unknown task source: " .. tostring(source(target)))
end

function M.identity(target) return provider(target).identity(target) end
function M.label(target)
  return target.repo .. (source(target) == "local" and "/task-" or "#") .. id(target)
end
function M.branch(target)
  return (source(target) == "local" and "task/" or "issue/") .. id(target)
end
function M.worktree(repo, number)
  return vim.fs.dirname(repo.root) .. "/" .. vim.fs.basename(repo.root) .. "-worktrees/"
    .. (source(repo) == "local" and "task-" or "") .. id({ number = number })
end

local function repository(root)
  local common = core().real(vim.trim(core().git(root, "rev-parse", "--path-format=absolute", "--git-common-dir")))
  local primary = core().worktrees(root)[1]
  assert(primary and primary.path, "No primary Git worktree")
  return { root = primary.path, common = common }
end

providers.github = {
  identity = function(target) return target.host .. "/" .. target.repo .. "#" .. id(target) end,
  repository = function(root)
    local repo = repository(root)
    local result = core().run({ "gh", "repo", "view", "--json", "nameWithOwner,url,defaultBranchRef" }, root)
    local info = vim.json.decode(result.stdout)
    repo.repo, repo.host, repo.url = info.nameWithOwner, info.url:match("^https?://([^/]+)"), info.url
    repo.default_branch = info.defaultBranchRef and info.defaultBranchRef.name
    return repo
  end,
  list = function(repo, query, limit)
    local argv = {
      "gh", "issue", "list", "--repo", repo.host .. "/" .. repo.repo, "--limit", tostring(limit),
      "--json", "number,title,url",
    }
    if query and query ~= "" then vim.list_extend(argv, { "--search", query }) end
    return vim.json.decode(core().run(argv, repo.root).stdout)
  end,
  get = function(target)
    return vim.json.decode(core().run({
      "gh", "issue", "view", id(target), "--repo", target.host .. "/" .. target.repo,
      "--json", "title,body,url",
    }, target.path or target.root).stdout)
  end,
  update = function(target, title, body)
    core().run({
      "gh", "issue", "edit", id(target), "--repo", target.host .. "/" .. target.repo,
      "--title", title, "--body-file", "-",
    }, target.path or target.root, false, body)
  end,
  create = function(repo, title, body)
    local result = core().run({
      "gh", "issue", "create", "--repo", repo.host .. "/" .. repo.repo, "--title", title, "--body-file", "-",
    }, repo.root, false, body or "")
    local url = vim.trim(result.stdout)
    local created_id = tonumber(url:match("^https?://" .. vim.pesc(repo.host .. "/" .. repo.repo) .. "/issues/(%d+)$"))
    assert(valid_id(created_id), "Unexpected issue URL; inspect GitHub before retrying: " .. url)
    return { source = "github", host = repo.host, repo = repo.repo, number = created_id, title = title,
      body = body or "", url = url, path = repo.root }
  end,
}

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
  local directory, files, seen = task_directory(target), {}, {}
  if not vim.uv.fs_stat(directory) then return files end
  for name, kind in vim.fs.dir(directory) do
    local id = number(name)
    if id and (kind == "file" or kind == "link") then
      assert(id > 0 and not seen[id], "Invalid or duplicate local task ID: " .. name)
      seen[id] = true
      files[#files + 1] = { number = id, task_file = name }
    end
  end
  table.sort(files, function(a, b) return a.number < b.number end)
  return files
end

local function slug(title)
  local value = title:lower():gsub("[^a-z0-9]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""):sub(1, 60)
  return value == "" and "task" or value
end

function M.file(target)
  assert(source(target) == "local", "Only local tasks have a source file")
  id(target)
  local name = target.task_file
  -- A remembered filename goes stale when the title (and so the file) is renamed.
  local stale = name and not name:find("/", 1, true) and number(name) == target.number
    and not vim.uv.fs_lstat(task_directory(target) .. "/" .. name)
  if not name or stale then
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
  identity = function(target)
    return "local:" .. assert(target.task_root or target.root, "Local task repository is missing") .. "#" .. id(target)
  end,
  repository = function(root)
    local repo = repository(root)
    repo.source, repo.task_root, repo.host, repo.repo = "local", repo.root, "local", vim.fs.basename(repo.root)
    return repo
  end,
  get = function(target)
    local path = M.file(target)
    local task = M.parse(vim.fn.readfile(path))
    task.url, task.task_file = path, vim.fs.basename(path)
    return task
  end,
  list = function(repo, query, limit)
    local items = {}
    for _, item in ipairs(task_files(repo)) do
      item.source, item.task_root = "local", repo.root
      local task = providers["local"].get(item)
      item.title, item.url = task.title, task.url
      if not query or query == "" or (task.title .. "\n" .. task.body):lower():find(query:lower(), 1, true) then
        items[#items + 1] = item
        if #items >= limit then break end
      end
    end
    return items
  end,
  update = function(target, title, body)
    core().write(M.file(target), "# " .. title .. "\n\n" .. body .. "\n")
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
      local path = M.file(task)
      local fd, err = vim.uv.fs_open(path, "wx", 384)
      assert(fd, "Cannot create local task: " .. tostring(err))
      local data = "# " .. title .. "\n\n" .. (body or "") .. "\n"
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

local function enabled(target)
  assert(source(target) ~= "github" or core().settings().github_enabled,
    "GitHub integration is disabled; set vim.g.pi_issues.github_enabled = true to enable it")
end

function M.repository(root, kind)
  local target = { source = kind == nil and "local" or kind }
  enabled(target)
  return provider(target).repository(root)
end
function M.list(repo, query, limit)
  enabled(repo)
  return provider(repo).list(repo, query, limit or 50)
end
function M.get(target)
  enabled(target)
  return provider(target).get(target)
end
function M.update(target, title, body)
  enabled(target)
  assert(type(title) == "string" and vim.trim(title) ~= "" and not title:find("[\r\n]"),
    "Enter a single-line task title")
  assert(type(body) == "string", "Task body must be Markdown text")
  return provider(target).update(target, title, body)
end
function M.delete(target)
  assert(source(target) == "local", "Only local tasks can be deleted")
  local path = M.file(target)
  if vim.uv.fs_stat(path) then assert(vim.uv.fs_unlink(path)) end
end
function M.create(repo, title, body)
  enabled(repo)
  assert(type(title) == "string" and vim.trim(title) ~= "" and not title:find("[\r\n]"),
    "Enter a single-line task title")
  assert(body == nil or type(body) == "string", "Task body must be Markdown text")
  return provider(repo).create(repo, title, body)
end

return M
