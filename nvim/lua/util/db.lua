-- Dadbod helpers for the Database menu (turbo/menus.lua) and the <leader>D
-- keymaps (plugins/editor.lua).
local M = {}

local sql = { sql = true, mysql = true, plsql = true }

-- query commands only make sense in a query buffer; say so instead of
-- letting dadbod-ui guess a connection
local function query_buffer()
  if vim.b.dbui_db_key_name or vim.b.db or sql[vim.bo.filetype] then
    return true
  end
  vim.notify("Not a query buffer - open one from the database UI (Space D u)", vim.log.levels.WARN)
end

-- runs :DB over range ("%" or "'<,'>") with the buffer's (or global) database
function M.execute(range)
  if not (vim.b.db or vim.g.db) then
    return vim.notify("No database for this buffer - open a query from the database UI (Space D u)", vim.log.levels.WARN)
  end
  if range ~= "%" and vim.fn.mode():match("^[vV\22]") then
    -- leave Visual mode first so '< and '> hold this selection
    vim.cmd("normal! \27")
  end
  require("lazy").load({ plugins = { "vim-dadbod-ui" } })
  vim.cmd(range .. "DB")
end

-- a DBUI command that needs a query buffer, e.g. M.in_query("DBUIRenameBuffer")
function M.in_query(command)
  return function()
    if query_buffer() then
      vim.cmd(command)
    end
  end
end

return M
