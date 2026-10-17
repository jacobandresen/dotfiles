-- Execute SQL through Dadbod UI when possible to retain bind parameters and history.
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

return M
