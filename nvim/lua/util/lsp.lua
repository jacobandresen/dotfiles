-- LSP helpers shared by keymaps and the Code menu.
local M = {}

local function compiler_fixits(buf)
  local filetype = vim.bo[buf].filetype
  if filetype ~= "c" and filetype ~= "cpp" then
    vim.notify("No file-wide fixes available", vim.log.levels.INFO)
    return
  end
  if not vim.bo[buf].modifiable or vim.bo[buf].readonly then
    vim.notify("This buffer cannot be changed", vim.log.levels.WARN)
    return
  end
  if vim.bo[buf].modified then
    vim.notify("Save the file before applying compiler fixes", vim.log.levels.WARN)
    return
  end

  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then
    vim.notify("Save the file before applying compiler fixes", vim.log.levels.WARN)
    return
  end
  file = vim.fn.fnamemodify(file, ":p")
  local compiler = filetype == "c" and "gcc" or "g++"
  if vim.fn.executable(compiler) ~= 1 then
    vim.notify(compiler .. " is needed for compiler fixes", vim.log.levels.WARN)
    return
  end

  local args = { compiler, "-fsyntax-only", "-fdiagnostics-parseable-fixits" }
  local flags = { filetype == "c" and "-std=gnu17" or "-std=gnu++17" }
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    if client.name == "clangd" then
      local fallback = client.config.init_options and client.config.init_options.fallbackFlags or {}
      vim.list_extend(flags, fallback)
      break
    end
  end
  vim.list_extend(args, flags)
  table.insert(args, file)

  local tick = vim.api.nvim_buf_get_changedtick(buf)
  vim.system(args, { cwd = vim.fn.fnamemodify(file, ":h"), text = true }, function(result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_get_changedtick(buf) ~= tick then
        vim.notify("Buffer changed while compiler fixes were being collected", vim.log.levels.WARN)
        return
      end
      local edits, seen = {}, {}
      for line in (result.stderr or ""):gmatch("[^\r\n]+") do
        local quoted_file, sl, sc, el, ec, quoted_text = line:match('^fix%-it:(".-"):{(%d+):(%d+)%-(%d+):(%d+)}:(".*")$')
        if quoted_file then
          local ok_file, target = pcall(vim.json.decode, quoted_file)
          local ok_text, replacement = pcall(vim.json.decode, quoted_text)
          if ok_file and ok_text and vim.fn.fnamemodify(target, ":p") == file then
            local edit = { tonumber(sl) - 1, tonumber(sc) - 1, tonumber(el) - 1, tonumber(ec) - 1, replacement }
            local key = table.concat(edit, "\0")
            if not seen[key] then
              seen[key] = true
              table.insert(edits, edit)
            end
          end
        end
      end
      if #edits == 0 then
        vim.notify("No automatic fixes available", vim.log.levels.INFO)
        return
      end
      table.sort(edits, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        return a[2] < b[2]
      end)
      local previous
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for _, edit in ipairs(edits) do
        local start_line, end_line = lines[edit[1] + 1], lines[edit[3] + 1]
        if not start_line or not end_line or edit[2] > #start_line or edit[4] > #end_line
          or edit[1] > edit[3] or (edit[1] == edit[3] and edit[2] > edit[4]) then
          vim.notify("Compiler returned an invalid edit; no changes applied", vim.log.levels.WARN)
          return
        end
        if previous and ((edit[1] < previous[3] or (edit[1] == previous[3] and edit[2] < previous[4]))
          or (edit[1] == previous[1] and edit[2] == previous[2])) then
          vim.notify("Compiler fixes overlap; no changes applied", vim.log.levels.WARN)
          return
        end
        previous = edit
      end
      for i = #edits, 1, -1 do
        local edit = edits[i]
        local ok, err = pcall(vim.api.nvim_buf_set_text, buf, edit[1], edit[2], edit[3], edit[4], vim.split(edit[5], "\n", { plain = true }))
        if not ok then
          vim.notify("Could not apply compiler fix: " .. err, vim.log.levels.ERROR)
          return
        end
      end
      vim.notify(string.format("Applied %d compiler fix%s", #edits, #edits == 1 and "" or "es"))
    end)
  end)
end

local function fallback(buf)
  if vim.bo[buf].filetype == "c" or vim.bo[buf].filetype == "cpp" then
    compiler_fixits(buf)
  else
    require("util.fix_all").run(buf)
  end
end

local function apply_action(choice, buf)
  if not choice or not vim.api.nvim_buf_is_valid(buf) then return end
  local client = vim.lsp.get_client_by_id(choice.client_id)
  if not client then return end
  local function apply(action)
    if action.edit then
      local ok, err = pcall(vim.lsp.util.apply_workspace_edit, action.edit, client.offset_encoding)
      if not ok then
        vim.notify("Could not apply LSP fix: " .. err, vim.log.levels.ERROR)
        return
      end
    end
    if action.command then
      client:exec_cmd(type(action.command) == "table" and action.command or action, choice.context)
    end
  end
  local action = choice.action
  if not (action.edit and action.command) and client:supports_method("codeAction/resolve") then
    client:request("codeAction/resolve", action, function(err, resolved)
      if err then
        if action.edit or action.command then apply(action)
        else vim.notify("Could not resolve LSP fix: " .. err.message, vim.log.levels.ERROR) end
      else
        apply(resolved)
      end
    end, buf)
  else
    apply(action)
  end
end

-- Prefer a language server's file-wide action, then use a language-specific
-- tool when the server has no applicable action.
function M.fix_all()
  local buf = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/codeAction" })
  if #clients == 0 then
    fallback(buf)
    return
  end
  local last = vim.api.nvim_buf_line_count(buf)
  local range = { start = { 1, 0 }, ["end"] = { last, #vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1] } }
  local kinds = { "source.fixAll" }
  if vim.bo[buf].filetype == "go" then table.insert(kinds, "source.organizeImports") end
  vim.lsp.buf_request_all(buf, "textDocument/codeAction", function(client)
    local params = vim.lsp.util.make_given_range_params(range.start, range["end"], buf, client.offset_encoding)
    local diagnostics = {}
    local namespace = vim.lsp.diagnostic.get_namespace(client.id)
    for _, diagnostic in ipairs(vim.diagnostic.get(buf, { namespace = namespace })) do
      if diagnostic.user_data and diagnostic.user_data.lsp then
        table.insert(diagnostics, diagnostic.user_data.lsp)
      end
    end
    params.context = { diagnostics = diagnostics, only = kinds, triggerKind = vim.lsp.protocol.CodeActionTriggerKind.Invoked }
    return params
  end, function(results)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local available = {}
    for client_id, entry in pairs(results) do
      for _, action in ipairs(entry.result or {}) do
        if not action.disabled and action.kind then
          for _, kind in ipairs(kinds) do
            if action.kind == kind or vim.startswith(action.kind, kind .. ".") then
              available[kind] = available[kind] or {}
              table.insert(available[kind], { action = action, client_id = client_id, context = entry.context })
            end
          end
        end
      end
    end
    for _, kind in ipairs(kinds) do
      if available[kind] then
        if vim.api.nvim_get_current_buf() ~= buf then
          vim.notify("Return to the original buffer to apply its LSP fixes", vim.log.levels.INFO)
          return
        end
        local choices = available[kind]
        if #choices == 1 then
          apply_action(choices[1], buf)
        else
          vim.ui.select(choices, {
            prompt = "File-wide fixes:",
            format_item = function(choice)
              local client = vim.lsp.get_client_by_id(choice.client_id)
              return choice.action.title .. " [" .. (client and client.name or "LSP") .. "]"
            end,
          }, function(choice) apply_action(choice, buf) end)
        end
        return
      end
    end
    fallback(buf)
  end)
end

return M
