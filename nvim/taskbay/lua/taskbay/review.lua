-- The changed-files picker of a task (or of the current repository): a diff preview of
-- each file, scoped to the working changes or everything since the recorded base.
local M = {}
local core = require("taskbay.core")
local tasks = require("taskbay.store")

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
      vim.notify("No " .. selected_scope .. " changes", vim.log.levels.INFO, { title = "Taskbay Review" })
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

return M
