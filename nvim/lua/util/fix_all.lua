-- File-scoped fallbacks when a language server has no source.fixAll action.
local M = {}

local function source(buf)
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  return text .. (vim.bo[buf].endofline and "\n" or "")
end

local function replace_buffer(buf, before, after, tick, label)
  if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_get_changedtick(buf) ~= tick then
    vim.notify("Buffer changed while fixes were being collected", vim.log.levels.WARN)
    return
  end
  if after == before then
    vim.notify("No automatic fixes available", vim.log.levels.INFO)
    return
  end
  local lines = vim.split(after, "\n", { plain = true })
  local endofline = after:sub(-1) == "\n"
  if endofline then table.remove(lines) end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].endofline = endofline
  vim.notify("Applied " .. label .. " fixes")
end

local function executable(name)
  local path = vim.fn.exepath(name)
  if path ~= "" then return path end
  local mason = vim.fn.stdpath("data") .. "/mason/bin/" .. name
  if vim.fn.executable(mason) == 1 then return mason end
end

local function marker(file, names)
  return vim.fs.find(names, { path = vim.fs.dirname(file), upward = true, type = "file" })[1]
end

local function read_disk(file)
  local handle = io.open(file, "rb")
  if not handle then return end
  local contents = handle:read("*a")
  handle:close()
  return contents
end

local function transform(buf, file, command, label)
  local before = source(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  vim.system(command, { cwd = vim.fs.dirname(file), stdin = before, text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 and (result.stdout or "") == "" then
        local message = vim.trim(result.stderr or "")
        vim.notify(label .. ": " .. (message ~= "" and message or "command failed"), vim.log.levels.WARN)
        return
      end
      local after = result.stdout
      if not after then
        vim.notify(label .. ": could not read fixes", vim.log.levels.WARN)
        return
      end
      replace_buffer(buf, before, after, tick, label)
    end)
  end)
end

local function eslint_fix(buf, file, eslint)
  if vim.bo[buf].modified then
    vim.notify("Save the JavaScript file before collecting ESLint fixes", vim.log.levels.WARN)
    return
  end
  local before, tick = source(buf), vim.api.nvim_buf_get_changedtick(buf)
  local disk = read_disk(file)
  if not disk or disk:gsub("\r\n", "\n") ~= before then
    vim.notify("JavaScript file changed on disk; reload or save it first", vim.log.levels.WARN)
    return
  end
  local output = vim.fn.tempname() .. ".json"
  vim.system({ eslint, file, "--fix-dry-run", "--format", "json", "--output-file", output },
    { cwd = vim.fs.dirname(file), text = true }, function(result)
      vim.schedule(function()
        local lines = vim.fn.filereadable(output) == 1 and vim.fn.readfile(output) or {}
        vim.uv.fs_unlink(output)
        if read_disk(file) ~= disk then
          vim.notify("JavaScript file changed on disk while fixes were being collected", vim.log.levels.WARN)
          return
        end
        local ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
        if not ok or type(data) ~= "table" or not data[1] then
          local message = vim.trim(result.stderr or "")
          vim.notify("ESLint: " .. (message ~= "" and message or "could not read fixes"), vim.log.levels.WARN)
          return
        end
        replace_buffer(buf, before, data[1].output or before, tick, "ESLint")
      end)
    end)
end

local function rust(buf, file)
  if vim.bo[buf].modified then
    vim.notify("Save the Rust file before collecting compiler fixes", vim.log.levels.WARN)
    return
  end
  local root = vim.fs.root(file, "Cargo.toml")
  if not root then
    vim.notify("Rust compiler fixes need a Cargo.toml", vim.log.levels.WARN)
    return
  end
  if not executable("cargo") then
    vim.notify("cargo is needed for Rust fixes", vim.log.levels.WARN)
    return
  end
  local before, tick = source(buf), vim.api.nvim_buf_get_changedtick(buf)
  local disk = read_disk(file)
  if not disk or disk:gsub("\r\n", "\n") ~= before then
    vim.notify("Rust file changed on disk; reload or save it first", vim.log.levels.WARN)
    return
  end
  local checker = executable("cargo-clippy") and "clippy" or "check"
  vim.system({ "cargo", checker, "--message-format=json" }, { cwd = root, text = true }, function(result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_get_changedtick(buf) ~= tick then
        vim.notify("Buffer changed while Rust fixes were being collected", vim.log.levels.WARN)
        return
      end
      if read_disk(file) ~= disk then
        vim.notify("Rust file changed on disk while fixes were being collected", vim.log.levels.WARN)
        return
      end
      local edits, seen = {}, {}
      local function collect(diagnostic)
        for _, span in ipairs(diagnostic.spans or {}) do
          local path = span.file_name
          if path and not path:match("^/") then path = root .. "/" .. path end
          if path and vim.fs.normalize(path) == vim.fs.normalize(file)
            and span.suggestion_applicability == "MachineApplicable" and span.suggested_replacement then
            local start, finish = span.byte_start, span.byte_end
            if type(start) == "number" and type(finish) == "number" and start >= 0 and finish <= #disk and start <= finish then
              local key = start .. ":" .. finish .. ":" .. span.suggested_replacement
              if not seen[key] then
                seen[key] = true
                table.insert(edits, { start, finish, span.suggested_replacement })
              end
            end
          end
        end
        for _, child in ipairs(diagnostic.children or {}) do collect(child) end
      end
      for line in (result.stdout or ""):gmatch("[^\r\n]+") do
        local ok, event = pcall(vim.json.decode, line)
        if ok and event.reason == "compiler-message" and event.message then collect(event.message) end
      end
      table.sort(edits, function(a, b) return a[1] < b[1] end)
      local after, previous = disk, nil
      for _, edit in ipairs(edits) do
        if previous and (edit[1] < previous[2] or edit[1] == previous[1]) then
          vim.notify("Rust suggestions overlap; no changes applied", vim.log.levels.WARN)
          return
        end
        previous = edit
      end
      for i = #edits, 1, -1 do
        local edit = edits[i]
        after = after:sub(1, edit[1]) .. edit[3] .. after:sub(edit[2] + 1)
      end
      if #edits == 0 and result.code ~= 0 then
        vim.notify("cargo " .. checker .. ": " .. vim.trim(result.stderr or "failed"), vim.log.levels.WARN)
        return
      end
      replace_buffer(buf, before, after:gsub("\r\n", "\n"), tick,
        checker == "clippy" and "Rust/Clippy" or "Rust compiler")
    end)
  end)
end

function M.run(buf)
  if not vim.bo[buf].modifiable or vim.bo[buf].readonly then
    vim.notify("This buffer cannot be changed", vim.log.levels.WARN)
    return
  end
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then
    vim.notify("Save the file before applying fixes", vim.log.levels.WARN)
    return
  end
  file = vim.fn.fnamemodify(file, ":p")
  local ft = vim.bo[buf].filetype
  if ft == "python" then
    local ruff = executable("ruff")
    if ruff then
      transform(buf, file, { ruff, "check", "--fix-only", "--stdin-filename", file, "-" }, "Ruff")
      return
    end
  elseif ft == "go" then
    local goimports = executable("goimports")
    if goimports then
      transform(buf, file, { goimports, "-srcdir", vim.fs.dirname(file) }, "Go imports")
      return
    end
  elseif ft == "rust" then
    rust(buf, file)
    return
  elseif vim.tbl_contains({ "javascript", "javascriptreact", "typescript", "typescriptreact" }, ft) then
    local eslint_config = marker(file, { "eslint.config.js", "eslint.config.mjs", "eslint.config.cjs",
      "eslint.config.ts", "eslint.config.mts", "eslint.config.cts", ".eslintrc", ".eslintrc.js",
      ".eslintrc.cjs", ".eslintrc.json", ".eslintrc.yaml", ".eslintrc.yml" })
    local eslint = eslint_config and vim.fs.dirname(eslint_config) .. "/node_modules/.bin/eslint"
    if not eslint or vim.fn.executable(eslint) ~= 1 then eslint = executable("eslint") end
    if eslint_config and eslint then
      eslint_fix(buf, file, eslint)
      return
    end
    local biome = executable("biome")
    if biome then
      transform(buf, file, { biome, "lint", "--write", "--stdin-file-path=" .. file }, "Biome")
      return
    end
  end
  vim.notify("No automatic fixes available for " .. ft, vim.log.levels.INFO)
end

return M
