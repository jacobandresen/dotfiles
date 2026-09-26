-- silently update plugins on startup (no notification, no UI window).
-- LazyVim sources this file at VeryLazy (or earlier when opening a file), so
-- a nested VeryLazy autocmd wouldn't reliably fire - just defer the call.
vim.schedule(function()
  require("lazy").update({ show = false, wait = false })
end)

-- auto-refresh log/jsonl files every 2 seconds
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*.log", "*.jsonl" },
  callback = function(args)
    local buf = args.buf
    if vim.b[buf].log_refresh then
      return -- already polling (e.g. after :e)
    end
    vim.b[buf].log_refresh = true
    vim.opt_local.autoread = true
    local timer = vim.uv.new_timer()
    timer:start(2000, 2000, vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        timer:stop()
        timer:close()
        return
      end
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("checktime")
      end)
    end))
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
      buffer = buf,
      once = true,
      callback = function()
        timer:stop()
        timer:close()
      end,
    })
  end,
})

-- autofix every quickfix-able diagnostic, bottom-to-top so an applied edit
-- can't shift a not-yet-processed one. Best-effort: takes the first action
-- offered per diagnostic rather than prompting.
local function fix_all_diagnostics()
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

-- <leader>cF next to LazyVim's <leader>ca (code action), only where LSP
-- offers code actions
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client and client:supports_method("textDocument/codeAction") then
      vim.keymap.set("n", "<leader>cF", fix_all_diagnostics, { buffer = args.buf, desc = "Fix All Diagnostics" })
    end
  end,
})
