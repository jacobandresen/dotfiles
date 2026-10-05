-- Run from the repo root: python3 nvim/tests/dadbod.py
-- Uses the real LazyVim config/plugins, with all writable data in a temp dir.
local api = vim.api
local db = require("util.db")
local notifications = {}
vim.notify = function(message) notifications[#notifications + 1] = tostring(message) end
local function check(condition, message) assert(condition, message) end
local function scalar(sql)
  local command = vim.env.DADBOD_TEST_URL
    and { "psql", vim.env.DADBOD_TEST_URL, "-X", "-At", "-c", sql }
    or { "sqlite3", vim.env.DADBOD_TEST_DB, sql }
  return vim.trim(vim.fn.system(command))
end
local function query(lines)
  vim.cmd.enew()
  api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.filetype = "sql"
  return api.nvim_get_current_buf()
end
local function result(expected)
  local found
  check(vim.wait(5000, function()
    for _, buf in ipairs(api.nvim_list_bufs()) do
      if vim.bo[buf].filetype == "dbout" or api.nvim_buf_get_name(buf):match("%.dbout$") then
        local text = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
        if text:find(expected, 1, true) then found = buf return true end
      end
    end
  end, 20), "Missing database result: " .. expected)
  return found
end
local function execute(buf, lines, expected, range)
  api.nvim_set_current_buf(buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if range then db.execute(range) else api.nvim_feedkeys(vim.keycode("<Space>De"), "xt", false) end
  result(expected)
end

if vim.env.DADBOD_TEST_CASE == "direct" then
  api.nvim_buf_set_lines(0, 0, -1, false, { "SELECT 'Direct cold start';" })
  vim.b.db = "sqlite:" .. vim.env.DADBOD_TEST_DB
  vim.cmd("%DB")
  result("Direct cold start")
  check(not require("lazy.core.config").plugins["vim-dadbod-ui"]._.loaded, "Direct DB need not load UI")
  print("PASS: cold-start :DB")
  vim.cmd("qa!")
  return
elseif vim.env.DADBOD_TEST_CASE == "connections" then
  db.edit_connections()
  check(notifications[#notifications]:find("No saved connections", 1, true), "Cold-start edit connections guard")
  print("PASS: cold-start edit connections")
  vim.cmd("qa!")
  return
end

check(not require("lazy.core.config").plugins["vim-dadbod-ui"]._.loaded, "UI should be lazy")
query({ "SELECT 1;" })
check(vim.g.vim_dadbod_completion_loaded == 1, "Completion must load on SQL FileType before opening DBUI")
check(vim.fn.exists(":DB") == 2, "Direct :DB must be available")
db.execute("%")
check(notifications[#notifications]:find("No database", 1, true), "Unconnected SQL must explain how to connect")
vim.cmd.enew()
db.execute("%")
check(notifications[#notifications]:find("Not a query buffer", 1, true), "Non-query guard")
query({ "SELECT 1;" })
db.in_query("DBUIRenameBuffer")()
check(notifications[#notifications]:find("assign", 1, true), "Rename must reject unassigned SQL")
db.edit_connections()
check(notifications[#notifications]:find("No saved connections", 1, true), "Missing connections guard")

local url = vim.env.DADBOD_TEST_URL or ("sqlite:" .. vim.env.DADBOD_TEST_DB)
vim.g.dbs = { fixture = url }
vim.cmd.DBUI()
check(vim.bo.filetype == "dbui", "Drawer opens")
local drawer = api.nvim_get_current_buf()
for _, item in ipairs(require("turbo.menus").db) do
  if type(item) == "table" and item.key then
    local key = " " .. item.key:gsub("^Space ", ""):gsub(" ", "")
    check(vim.fn.maparg(key, "n") ~= "", "Menu shortcut must exist: " .. item.key)
  end
end
local function activate(text)
  api.nvim_set_current_buf(drawer)
  for row, line in ipairs(api.nvim_buf_get_lines(drawer, 0, -1, false)) do
    if line:find(text, 1, true) then
      api.nvim_win_set_cursor(0, { row, 0 })
      vim.cmd("normal \r")
      return
    end
  end
  error("Missing drawer item: " .. text)
end
activate("fixture")
activate("New query")
local buf = api.nvim_get_current_buf()
check(vim.bo.filetype == "sql" and vim.b.dbui_db_key_name, "New query is connected")
check(vim.fn.maparg("<Plug>(DBUI_ExecuteQuery)", "n") ~= "", "Native query mapping")
check(vim.fn.maparg("<leader>S", "n", false, true).buffer ~= 1, "No conflicting default SQL mapping")
execute(buf, { "SELECT name FROM people WHERE id = 1;" }, "Ada")
api.nvim_set_current_buf(result("Ada"))
check(vim.fn["db_ui#statusline"]() ~= nil, "Result metadata")
db.execute("%")
check(notifications[#notifications]:find("Not a query buffer", 1, true), "Results must not be executable")
api.nvim_set_current_buf(buf)
-- Editing an empty parameter set must explain itself without an exception.
db.query_action("<Plug>(DBUI_EditBindParameters)")()
vim.b.dbui_bind_params = { [":id"] = "2" }
execute(buf, { "SELECT name FROM people WHERE id = :id;" }, "Grace")
vim.cmd.DBUILastQueryInfo()
check(vim.fn.execute("messages"):find("SELECT name FROM people WHERE id = :id;", 1, true), "Last query records DBUI execution")

-- Drive Visual mode, rather than manually fabricating '< and '> marks.
api.nvim_set_current_buf(buf)
api.nvim_buf_set_lines(buf, 0, -1, false, {
  "INSERT INTO people VALUES (3, 'Selected');",
  "INSERT INTO people VALUES (4, 'Must not run');",
})
api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd("normal! V")
db.execute("'<,'>")
check(vim.wait(5000, function()
  return scalar("SELECT count(*) FROM people WHERE id IN (1, 2, 3);") == "3"
    and scalar("SELECT count(*) FROM people WHERE id = 4;") == "0"
end, 20), "Visual execution must run only selected SQL")
api.nvim_set_current_buf(buf)
api.nvim_buf_set_lines(buf, 0, -1, false, { "INSERT INTO people VALUES (5, 'Save only');" })
vim.cmd.write()
vim.wait(100)
check(scalar("SELECT count(*) FROM people;") == "3", "Saving must not execute")
-- Answer the real save prompt, then verify disk content and reassignment.
vim.fn.feedkeys("saved-query.sql\r", "nt")
db.query_action("<Plug>(DBUI_SaveQuery)")()
check(vim.fn.expand("%:t") == "saved-query.sql", "Save query opens the saved file")
check(vim.fn.readfile(vim.fn.expand("%"))[1]:find("Save only", 1, true), "Saved SQL content")
check(vim.b.dbui_db_key_name ~= nil, "Saved query retains its connection")
check(scalar("SELECT count(*) FROM people;") == "3", "Save query must not execute")
buf = api.nvim_get_current_buf()

-- Real Blink provider: verify schema/table and column completions.
require("lazy").load({ plugins = { "blink.cmp" } })
local source = require("vim_dadbod_completion.blink").new()
local function complete(line, label)
  api.nvim_set_current_buf(buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  api.nvim_win_set_cursor(0, { 1, #line - 1 })
  local found = false
  check(vim.wait(5000, function()
    source:get_completions({ cursor = { 1, #line }, line = line }, function(response)
      for _, item in ipairs(response.items) do
        if item.label == label then found = true end
      end
    end)
    return found
  end, 50), "Missing completion: " .. label)
end
complete("SELECT * FROM pe", "people")
complete("SELECT people.na", "name")

-- Standalone SQL retains plain Dadbod support for an explicit buffer URL.
local standalone = query({ "SELECT 'Standalone works';" })
vim.b.db = url
db.execute("%")
result("Standalone works")
api.nvim_set_current_buf(standalone)
vim.cmd.DBUIFindBuffer()
check(vim.b.dbui_db_key_name ~= nil, "Existing SQL can be assigned with Find Buffer")

vim.fn.feedkeys("sqlite:" .. vim.env.DADBOD_TEST_SECOND_DB .. "\r\21persisted\r", "nt")
vim.cmd.DBUIAddConnection()
local persisted = vim.json.decode(table.concat(vim.fn.readfile(vim.g.db_ui_save_location .. "/connections.json"), "\n"))
check(persisted[1].name == "persisted", "Add connection persists its name")
db.edit_connections()
check(vim.fn.expand("%:t") == "connections.json", "Edit saved connections")
vim.cmd.DBUIClose()
vim.cmd.DBUIToggle()
check(vim.bo.filetype == "dbui", "Toggle reopens drawer")
vim.cmd("normal R")
local connections = vim.fn["db_ui#connections_list"]()
check(vim.iter(connections):any(function(connection) return connection.name == "persisted" end), "Saved connections reload into the drawer: " .. vim.inspect(connections))
print("PASS: Dadbod real database queries, visual selection, bind parameters, history, completion, persistence, guards and drawer")
vim.cmd("qa!")
