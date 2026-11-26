-- GitHub driver for remote issue trackers, through the gh CLI.
--
-- A driver is a module taskbay/remotes/<name>.lua; the name is the target's `source`.
-- Everything above the driver (import, drafts, Fields, publish, export) uses only this
-- interface and the normalised issue shape, so another tracker (GitLab: glab) is one file.
--
--   title, glyph                       display name and Nerd Font icon
--   repository(root) -> repo           tasks.checkout(root) plus repo ("owner/name"), host, url,
--                                      default_branch
--   list(repo, query, limit) -> issues open issues: { number, title, url, state, labels }
--   get(target) -> issue               one issue, normalised (below)
--   update(target, title, body, changes)
--                                      changes: add_labels, remove_labels, add_assignees,
--                                      remove_assignees (lists), milestone ("" clears), state
--   create(repo, title, body) -> target
--
-- Normalised issue: number, title, body, url, state ("open" / "closed"), labels and
-- assignees (lists of names), milestone (name or nil), author, created_at, updated_at,
-- closed_at, comments (count) and raw: the tracker's own data, kept verbatim.
local M = { title = "GitHub", glyph = "\u{f09b}" }
local function core() return require("taskbay.core") end
local function tasks() return require("taskbay.store") end

-- gh prints JSON null for missing values; decode those as nil, not vim.NIL.
local function decode(text) return vim.json.decode(text, { luanil = { object = true, array = true } }) end
local function slug(target) return target.host .. "/" .. target.repo end
local function names(list, key) return vim.tbl_map(function(entry) return entry[key] end, list or {}) end

function M.normalise(raw)
  return {
    number = raw.number, title = raw.title, body = raw.body or "", url = raw.url,
    state = (raw.state or "open"):lower(), -- gh reports OPEN / CLOSED
    labels = names(raw.labels, "name"), assignees = names(raw.assignees, "login"),
    milestone = raw.milestone and raw.milestone.title, author = raw.author and raw.author.login,
    created_at = raw.createdAt, updated_at = raw.updatedAt, closed_at = raw.closedAt,
    comments = raw.comments and #raw.comments, raw = raw,
  }
end

function M.repository(root)
  local repo = tasks().checkout(root)
  local info = decode(core().run({ "gh", "repo", "view", "--json", "nameWithOwner,url,defaultBranchRef" }, root).stdout)
  repo.repo, repo.host, repo.url = info.nameWithOwner, info.url:match("^https?://([^/]+)"), info.url
  repo.default_branch = info.defaultBranchRef and info.defaultBranchRef.name
  return repo
end

function M.list(repo, query, limit)
  local argv = { "gh", "issue", "list", "--repo", slug(repo), "--limit", tostring(limit), "--json", "number,title,url,labels,state" }
  if query and query ~= "" then vim.list_extend(argv, { "--search", query }) end
  return vim.tbl_map(M.normalise, decode(core().run(argv, repo.root).stdout))
end

function M.get(target)
  -- Everything gh exposes about the issue; imports keep it verbatim (raw).
  return M.normalise(decode(core().run({
    "gh", "issue", "view", tostring(target.number), "--repo", slug(target),
    "--json", "assignees,author,body,closed,closedAt,comments,createdAt,id,labels,milestone,"
      .. "number,projectItems,state,stateReason,title,updatedAt,url",
  }, target.path or target.root).stdout))
end

function M.update(target, title, body, changes)
  changes = changes or {}
  local argv = { "gh", "issue", "edit", tostring(target.number), "--repo", slug(target), "--title", title, "--body-file", "-" }
  for key, flag in pairs({ add_labels = "--add-label", remove_labels = "--remove-label",
    add_assignees = "--add-assignee", remove_assignees = "--remove-assignee" }) do
    for _, value in ipairs(changes[key] or {}) do vim.list_extend(argv, { flag, value }) end
  end
  if changes.milestone then
    vim.list_extend(argv, changes.milestone == "" and { "--remove-milestone" } or { "--milestone", changes.milestone })
  end
  local cwd = target.path or target.root
  core().run(argv, cwd, false, body)
  -- gh issue edit has no state flag: state changes are gh issue close / reopen.
  if changes.state then
    core().run({ "gh", "issue", changes.state == "closed" and "close" or "reopen", tostring(target.number),
      "--repo", slug(target) }, cwd)
  end
end

function M.create(repo, title, body)
  local result = core().run({ "gh", "issue", "create", "--repo", slug(repo), "--title", title, "--body-file", "-" },
    repo.root, false, body or "")
  local url = vim.trim(result.stdout)
  local number = tonumber(url:match("^https?://" .. vim.pesc(slug(repo)) .. "/issues/(%d+)$"))
  assert(tasks().valid_id(number), "Unexpected issue URL; inspect GitHub before retrying: " .. url)
  return { source = "github", host = repo.host, repo = repo.repo, number = number, title = title,
    body = body or "", url = url, path = repo.root }
end

return M
