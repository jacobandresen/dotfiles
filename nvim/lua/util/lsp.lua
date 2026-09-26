-- LSP helpers shared by keymaps (config/autocmds.lua) and the Code menu.
local M = {}

-- autofix every quickfix-able diagnostic, bottom-to-top so an applied edit
-- can't shift a not-yet-processed one. Best-effort: takes the first action
-- offered per diagnostic rather than prompting.
function M.fix_all()
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/codeAction" })
  if #clients == 0 then
    vim.notify("No LSP client here supports code actions", vim.log.levels.WARN)
    return
  end

  local diagnostics = vim.diagnostic.get(bufnr)
  table.sort(diagnostics, function(a, b) return a.lnum > b.lnum end)

  local fixed, skipped = 0, 0
  for _, diag in ipairs(diagnostics) do
    local lsp_diag = diag.user_data and diag.user_data.lsp
    local applied = false

    if lsp_diag then
      for _, client in ipairs(clients) do
        local start_pos = { diag.lnum + 1, diag.col }
        local end_pos = { (diag.end_lnum or diag.lnum) + 1, diag.end_col or diag.col }
        local params = vim.lsp.util.make_given_range_params(start_pos, end_pos, bufnr, client.offset_encoding)
        params.context = { diagnostics = { lsp_diag }, only = { "quickfix" } }

        local resp = client:request_sync("textDocument/codeAction", params, 2000, bufnr)
        local actions = resp and resp.result or {}
        local action = actions[1]
        if action then
          if not (action.edit and action.command) and client:supports_method("codeAction/resolve") then
            local resolved = client:request_sync("codeAction/resolve", action, 2000, bufnr)
            action = (resolved and resolved.result) or action
          end
          if action.edit then
            vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
          end
          if action.command then
            client:exec_cmd(type(action.command) == "table" and action.command or action, { bufnr = bufnr })
          end
          applied = true
          break
        end
      end
    end

    if applied then fixed = fixed + 1 else skipped = skipped + 1 end
  end

  vim.notify(("Autofix: %d fixed, %d left"):format(fixed, skipped), vim.log.levels.INFO)
end

return M
