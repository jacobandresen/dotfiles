-- Dadbod helpers for the Database menu (turbo/menus.lua) and the <leader>D
-- keymaps (plugins/editor.lua).
local M = {}

local sql = { sql = true, mysql = true, plsql = true }

-- query commands only make sense in a query buffer; say so instead of
-- letting dadbod-ui guess a connection
local function query_buffer()
  if vim.bo.buftype == "" and (sql[vim.bo.filetype] or vim.b.dbui_db_key_name) then
    return true
  end
  vim.notify("Not a query buffer - open one from the database UI (Space D u)", vim.log.levels.WARN)
end

-- DBUI exposes buffer-local Ex actions through its public <Plug> mappings.
local function run_mapping(mapping)
  local command = mapping.rhs:gsub("^:<C%-[uU]>", ""):gsub("^:", ""):gsub("<CR>$", "")
  command = command:gsub("<[sS][iI][dD]>", "<SNR>" .. mapping.sid .. "_")
  vim.cmd(command)
end

-- Runs the selection or whole buffer, including DBUI parameters and history.
function M.execute(range)
  if not query_buffer() then return end
  require("lazy").load({ plugins = { "vim-dadbod-ui" } })
  if vim.fn.empty(vim.b.db or "") == 1 and vim.fn.empty(vim.g.db or "") == 1
    and vim.fn.empty(vim.w.db or "") == 1 and vim.fn.empty(vim.t.db or "") == 1
    and vim.fn.empty(vim.env.DATABASE_URL or "") == 1 then
    return vim.notify("No database for this buffer - open a query from the database UI (Space D u)", vim.log.levels.WARN)
  end
  if range ~= "%" and vim.fn.mode():match("^[vV\22]") then
    -- leave Visual mode first so '< and '> hold this selection
    vim.cmd("normal! \27")
  end
  -- Use DBUI's public mapping so bind parameters and last-query info work.
  -- Execute its Ex action directly: queued keys can run in the result window.
  local mode = range == "%" and "n" or "x"
  local mapping = vim.fn.maparg("<Plug>(DBUI_ExecuteQuery)", mode, false, true)
  if vim.b.dbui_db_key_name and mapping.rhs then
    run_mapping(mapping)
  else
    vim.cmd(range .. "DB")
  end
end

function M.query_action(plug)
  return function()
    if not query_buffer() then return end
    local mapping = vim.fn.maparg(plug, "n", false, true)
    if not vim.b.dbui_db_key_name or not mapping.rhs then
      return vim.notify("This action needs a database UI query (Space D u); use :write for an existing SQL file", vim.log.levels.WARN)
    end
    run_mapping(mapping)
  end
end

-- the connections Space D a saved (db_ui_save_location, outside git)
function M.edit_connections()
  require("lazy").load({ plugins = { "vim-dadbod-ui" } })
  local file = vim.g.db_ui_save_location .. "/connections.json"
  if vim.fn.filereadable(file) == 0 then
    return vim.notify("No saved connections yet - add one with Space D a", vim.log.levels.WARN)
  end
  vim.cmd.edit(vim.fn.fnameescape(file))
  vim.notify("Press R in the database UI to reload it after saving")
end

-- a DBUI command that needs a query buffer, e.g. M.in_query("DBUIRenameBuffer")
function M.in_query(command)
  return function()
    if not query_buffer() then return end
    if command == "DBUIRenameBuffer" and not vim.b.dbui_db_key_name then
      return vim.notify("Open or assign this query in the database UI first (Space D f)", vim.log.levels.WARN)
    end
    vim.cmd(command)
  end
end

return M
