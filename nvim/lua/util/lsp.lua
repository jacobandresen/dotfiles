-- LSP helpers shared by keymaps and the Code menu.
local M = {}

-- Ask the server for a coherent document-wide fix instead of applying
-- arbitrary per-diagnostic actions. Neovim routes diagnostics per client,
-- requests asynchronously, resolves actions and prompts for alternatives.
function M.fix_all()
  if #vim.lsp.get_clients({ bufnr = 0, method = "textDocument/codeAction" }) == 0 then
    vim.notify("No LSP client here supports code actions", vim.log.levels.WARN)
    return
  end
  local last = vim.api.nvim_buf_line_count(0)
  vim.lsp.buf.code_action({
    context = { only = { "source.fixAll" } },
    range = { start = { 1, 0 }, ["end"] = { last, #vim.api.nvim_buf_get_lines(0, last - 1, last, false)[1] } },
    filter = function(action) return not action.disabled end,
    apply = true,
  })
end

return M
