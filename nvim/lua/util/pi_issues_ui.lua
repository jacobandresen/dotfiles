local M = {}
local core = require("util.pi_issues")
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
        and (vim.fs.basename(workspace.repo) .. "#" .. workspace.number .. " " .. core.status(workspace))
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
  local model = job and job.model or "Luna"
  if model == "github-copilot/gpt-5.6-luna" then model = "Luna" end
  return safe(("Pi %d | %s | %s"):format(workspace.number, core.status(workspace), model))
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
      title = (workspace and (workspace.repo .. "#" .. workspace.number .. " - ") or "")
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
          if not workspace then return vim.notify("Issue scope is available in an issue tab", vim.log.levels.WARN) end
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
            ["<C-g>"] = { "issue_scope", mode = { "i", "n" }, desc = "Working / Issue Changes" },
            ["<C-r>"] = { "refresh_issue", mode = { "i", "n" }, desc = "Refresh Diff" },
          },
        },
      },
    })
  end)
end

local function draw()
  if not dashboard or not vim.api.nvim_buf_is_valid(dashboard) then return end
  local current_id
  for _, win in ipairs(vim.fn.win_findbuf(dashboard)) do
    local row = vim.api.nvim_win_get_cursor(win)[1]
    current_id = dashboard_rows[row] and dashboard_rows[row].id
  end
  local items = vim.tbl_values(core.workspaces)
  table.sort(items, function(a, b) return a.repo == b.repo and a.number < b.number or a.repo < b.repo end)
  local active, waiting = 0, 0
  for _, job in pairs(core.jobs) do
    if not job.exited then active = active + 1 end
    if job.activity == "waiting" then waiting = waiting + 1 end
  end
  local wins = vim.fn.win_findbuf(dashboard)
  local width = #wins > 0 and vim.api.nvim_win_get_width(wins[1]) or 100
  local repo_width = math.min(28, math.floor(width * 0.3))
  local title_width = math.max(8, width - repo_width - 26)
  local format = "  %-" .. repo_width .. "s  %-10s %5s  %s"
  local lines = {
    "  Pi workspaces",
    ("  %d active / %d slots    %d waiting    %d workspaces"):format(
      active,
      core.settings().max_agents,
      waiting,
      #items
    ),
    "",
    "  Worktrees and conversations are kept when agents stop.",
    string.format(format, "ISSUE", "AGENT", "FILES", "TITLE"),
  }
  dashboard_rows = {}
  local selected = 6
  for _, workspace in ipairs(items) do
    lines[#lines + 1] = string.format(
      format,
      clip(workspace.repo .. "#" .. workspace.number, repo_width),
      core.status(workspace),
      workspace.refreshing and "..." or (workspace.files and tostring(workspace.files) or "?"),
      clip(workspace.title, title_width)
    )
    dashboard_rows[#lines] = workspace
    if workspace.id == current_id then selected = #lines end
  end
  if #items == 0 then lines[#lines + 1] = "  No workspaces yet. Press i to choose issues." end
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
  for row, workspace in pairs(dashboard_rows) do
    local status = core.status(workspace)
    local group = (status == "error" or status == "missing") and "DiagnosticError"
      or status == "waiting" and "DiagnosticWarn"
      or status == "working" and "DiagnosticInfo"
      or "Comment"
    highlight(row - 1, repo_width + 4, group, repo_width + 14)
  end
  for _, win in ipairs(vim.fn.win_findbuf(dashboard)) do
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
      title = " Pi Workspaces ",
      title_pos = "center",
      footer = size.width >= 64 and " Enter open  p pi  d diff  i issues  ? help  q close "
        or " Enter open  p pi  d diff  ? help ",
      footer_pos = "center",
    })
  )
  resize_with_editor(win, 112, height, draw)
  vim.wo.number, vim.wo.relativenumber, vim.wo.wrap, vim.wo.cursorline = false, false, false, true
  vim.wo.winblend, vim.wo.signcolumn = 0, "no"
  local function selected() return dashboard_rows[vim.api.nvim_win_get_cursor(0)[1]] end
  local function action(fn)
    return function()
      local workspace = selected()
      if workspace then
        vim.cmd.close()
        fn(workspace)
      end
    end
  end
  local function refresh()
    for _, workspace in pairs(core.workspaces) do
      core.task(function() core.refresh(workspace) end)
    end
    draw()
  end
  local maps = {
    ["<CR>"] = action(function(w)
      core.task(function()
        core.validate(w)
        core.open(w)
      end)
    end),
    p = action(function(w)
      core.task(function() core.start(w) end)
    end),
    d = action(function(w) M.review(w) end),
    D = action(function(w) M.review(w, "issue") end),
    x = action(function(w)
      core.task(function()
        if
          core.choose({ "Cancel", "Stop pi; keep worktree and session" }, "Stop " .. w.repo .. "#" .. w.number .. "?")
          == "Stop pi; keep worktree and session"
        then
          core.stop(w)
        end
      end)
    end),
    r = refresh,
    ["?"] = function()
      vim.lsp.util.open_floating_preview({
        "# Pi workspaces",
        "",
        "Enter: open code tab    p: start / focus pi",
        "d: working diff        D: issue diff (recorded base)",
        "x: stop with confirmation; never delete work",
        "r: refresh file counts i: choose more issues",
        "",
        "Space a p: hide / show pi without stopping it",
        "Space a s: paste context; Enter in pi submits it",
        "Space a r: paste a foreground reviewer request",
        "",
        "Agent state does not verify tests or mark an issue complete.",
      }, "markdown", { border = "rounded", max_width = 64 })
    end,
    i = function()
      vim.api.nvim_win_close(win, false)
      M.issues()
    end,
    q = function() vim.cmd.close() end,
    ["<Esc>"] = function() vim.cmd.close() end,
  }
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
      title = " Review Issue Launch ",
      title_pos = "center",
      footer = " s start / Enter prepare only / q cancel ",
      footer_pos = "center",
    })
  )
  resize_with_editor(win, 100, #lines + 2)
  vim.wo.wrap, vim.wo.linebreak, vim.wo.signcolumn = true, true, "no"
  vim.api.nvim_buf_set_extmark(buf, accents, 0, 0, { end_col = #lines[1], hl_group = "Title" })
  local finished = false
  local function finish(choice)
    if finished then return end
    finished = true
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    vim.schedule(function()
      local ok, err = coroutine.resume(thread, choice)
      if not ok then vim.notify(tostring(err), vim.log.levels.ERROR, { title = "Pi Issues" }) end
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

function M.launch(repo, issues)
  core.task(function()
    local default = repo.default_branch and ("origin/" .. repo.default_branch) or ""
    local ref = core.input("Base ref (locally cached; no automatic fetch): ", default)
    if not ref then return end
    local sha = core.base(repo, ref)
    assert(sha, "Base ref is unavailable: " .. ref .. ". Fetch explicitly or choose an existing ref.")
    local summary = { repo.host .. "/" .. repo.repo, "", "Base: " .. ref .. " (" .. sha:sub(1, 12) .. ")", "" }
    local trees = core.worktrees(repo.root)
    for _, issue in ipairs(issues) do
      summary[#summary + 1] = ("%d %s -> issue/%d"):format(issue.number, core.clean(issue.title), issue.number)
      local path = vim.fs.dirname(repo.root) .. "/" .. vim.fs.basename(repo.root) .. "-worktrees/" .. issue.number
      for _, tree in ipairs(trees) do
        if tree.branch == "issue/" .. issue.number then path = tree.path end
      end
      summary[#summary + 1] = "   " .. path
      summary[#summary + 1] = ""
    end
    summary[#summary + 1] = "Existing matching branches/worktrees will be reused; your main checkout is not changed."
    summary[#summary + 1] = "Start sends issue context to GitHub Copilot Luna. Limit: "
      .. core.settings().max_agents
      .. " live issue agents."
    local choice = M.confirm_launch(summary)
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
              "Prepared " .. workspace.repo .. "#" .. workspace.number .. "; start from Space a w when a slot is free",
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
      { title = "Pi issue launch" }
    )
  end)
end

function M.issues(query, limit, repository)
  local root = repository and repository.root or core.root()
  limit = limit or 50
  core.task(function()
    local repo = repository or core.repository(root)
    local argv = {
      "gh",
      "issue",
      "list",
      "--repo",
      repo.host .. "/" .. repo.repo,
      "--limit",
      tostring(limit),
      "--json",
      "number,title,url,labels,updatedAt",
    }
    if query and query ~= "" then vim.list_extend(argv, { "--search", query }) end
    local result = core.run(argv, root)
    local items = vim.json.decode(result.stdout)
    for _, issue in ipairs(items) do
      issue.text = ("%d %s"):format(issue.number, core.clean(issue.title))
    end
    local title = repo.repo .. " / Issues"
    if #items == 0 then
      title = (query and query ~= "" and "No matching open issues / " or "No open issues / ") .. repo.repo
    end
    Snacks.picker({
      title = title,
      items = items,
      show_empty = true,
      format = "text",
      layout = { preset = "select" },
      footer = "Tab select / Enter continue / C-s search GitHub / C-l load 50 more",
      confirm = function(picker)
        local selected = picker:selected({ fallback = true })
        picker:close()
        if #selected > 0 then M.launch(repo, selected) end
      end,
      actions = {
        server_search = function(picker)
          picker:close()
          core.task(function()
            local search = core.input("GitHub issue search: ", query or "")
            if search then M.issues(search, limit, repo) end
          end)
        end,
        more_issues = function(picker)
          picker:close()
          M.issues(query, limit + 50, repo)
        end,
      },
      win = {
        input = {
          keys = {
            ["<C-s>"] = { "server_search", mode = { "n", "i" } },
            ["<C-l>"] = { "more_issues", mode = { "n", "i" } },
          },
        },
      },
    })
  end)
end

function M.install()
  if vim.fn.executable("npm") ~= 1 then
    return vim.notify("npm is required to install pi-subagents", vim.log.levels.ERROR)
  end
  core.task(function()
    local result = core.run({ "npm", "ci", "--ignore-scripts", "--omit=dev" }, core.path())
    vim.notify(
      "Pinned pi-subagents installed. Use Space a i to choose issues.\n" .. vim.trim(result.stdout),
      vim.log.levels.INFO
    )
  end)
end

function M.setup()
  core.setup()
  core.load()
  vim.api.nvim_create_user_command(
    "PiIssues",
    function(opts) M.issues(opts.args) end,
    { nargs = "?", desc = "Choose GitHub issues" }
  )
  vim.api.nvim_create_user_command("PiWorkspaces", M.dashboard, { desc = "Pi issue workspace dashboard" })
  vim.api.nvim_create_user_command("PiIssuesSetup", M.install, { desc = "Install pinned pi extension dependencies" })
  vim.api.nvim_create_user_command("PiQuit", core.quit, { desc = "Confirm stopping managed agents and quit safely" })
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
