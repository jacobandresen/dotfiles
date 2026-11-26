-- pi agent driver (https://github.com/earendil-works/pi).
--
-- An agent driver is a module taskbay.agents.<name>; settings.agent picks it. Core starts
-- the command in a terminal inside the task's worktree and watches the status file the
-- agent writes (JSON: version 1, run, sequence, activity idle/working/waiting/exited,
-- outcome, cwd, session, session_file, model). Here pi reports through the bundled
-- extension (agents/pi/extension.ts).
--
--   title                          display name
--   check()                        assert the agent can start
--   command(spec) -> argv          spec: session, session_file, name, prompt_file (new
--                                  conversations only)
--   env(status_file, run) -> env   process environment for status reporting
--   session_matches(file, workspace) -> bool
--                                  a saved session belongs to the workspace
--   terminal() -> argv             a standalone agent outside any task
--   review(model) -> text          request for a read-only review of the task's changes
--   delegation                     rule appended to every task prompt
--   install()                      one-time setup, run in a task() coroutine (optional)
local M = { title = "Pi" }
local function core() return require("taskbay.core") end

-- The extension and its pinned npm dependencies.
M.dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h:h") .. "/agents/pi"

-- settings.pi: cmd (default "pi"), args (extra arguments, e.g. a theme), provider, model.
local function options() return vim.tbl_extend("force", { cmd = "pi", args = {} }, core().settings().pi or {}) end

function M.check()
  assert(vim.fn.executable(options().cmd) == 1, "pi is not installed")
  assert(vim.uv.fs_stat(M.dir .. "/node_modules/pi-subagents/bundle/index.js"),
    "Run :TaskbaySetup to install the pinned pi extension")
end

local function base()
  local opts = options()
  return vim.list_extend({ opts.cmd }, opts.args), opts
end

function M.command(spec)
  local argv, opts = base()
  vim.list_extend(argv, { "--extension", M.dir .. "/extension.ts" })
  if opts.provider then vim.list_extend(argv, { "--provider", opts.provider }) end
  if opts.model then vim.list_extend(argv, { "--model", opts.model }) end
  if spec.session_file then
    vim.list_extend(argv, { "--session", spec.session_file })
  else
    vim.list_extend(argv, { "--session-id", spec.session, "--name", spec.name })
  end
  if spec.prompt_file then vim.list_extend(argv, { "--", "@" .. spec.prompt_file, "Implement the attached task." }) end
  return argv
end

function M.env(status_file, run) return { NVIM_PI_STATUS = status_file, NVIM_PI_RUN = run } end

function M.session_matches(file, workspace)
  local header = vim.json.decode(vim.fn.readfile(file, "", 1)[1] or "")
  return header.type == "session" and type(header.cwd) == "string"
    and core().real(header.cwd) == workspace.path and header.id == workspace.session
end

function M.terminal() return (base()) end

function M.review(model)
  return "Use the existing subagent tool with agent: reviewer, async: false, model: " .. model
    .. " and the current cwd. Review this task's changes against its description and repository instructions. "
    .. "Do not edit files, use workflow scripts, or start background agents."
end

M.delegation = "If explicitly asked to delegate, use pi-subagents in the foreground with async: false, "
  .. "the current cwd, an explicit provider/model ID matching your active session model, "
  .. "and no managed worktree. Do not start background or external agents."

function M.install()
  assert(vim.fn.executable("npm") == 1, "npm is required to install pi-subagents")
  local result = core().run({ "npm", "ci", "--ignore-scripts", "--omit=dev" }, M.dir)
  return "Pinned pi-subagents installed.\n" .. vim.trim(result.stdout)
end

return M
