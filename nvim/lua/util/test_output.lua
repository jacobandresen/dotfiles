local M = {}
local client, buf, win, selected
local active = {}
local polling = false

local function visible() return win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf end

local function text(value)
  return value
    :gsub("\27%[[0-?]*[ -/]*[@-~]", "")
    :gsub("\27%][^\7\27]*[\7]", "")
    :gsub("\27%][^\27]*\27\\", "")
    :gsub("\r\n", "\n")
    :gsub("\r", "\n")
    :gsub("[%z\1-\8\11\12\14-\31\127]", "")
end

local function read(path)
  local file, err = io.open(path, "rb")
  if not file then return nil, err end
  local size = file:seek("end")
  local offset = math.max(0, size - 1024 * 1024)
  file:seek("set", offset)
  local content = file:read("*a")
  file:close()
  return (offset > 0 and "Output truncated: showing the last 1 MiB.\n" or "") .. content
end

function M.refresh()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local content = selected and selected.text or "Run a test to see its output."
  if selected and selected.file then
    local output, err = read(selected.file)
    if output then
      content = (selected.text and selected.text .. "\n\n" or "") .. output
    else
      content = "Cannot read test output: " .. tostring(err)
      if not selected.read_error then
        selected.read_error = true
        vim.notify(content, vim.log.levels.ERROR, { title = "Tests" })
      end
    end
  end
  content = text(content)
  if content == "" then
    content = selected and selected.running and "Test process running; waiting for output." or "No output."
  end
  local lines = vim.split(content, "\n", { plain = true })
  local follow = visible() and vim.api.nvim_win_get_cursor(win)[1] >= vim.api.nvim_buf_line_count(buf)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  if visible() then
    local name = selected and selected.source and vim.fs.basename(selected.source) or ""
    vim.wo[win].winbar = "%#Title# Output %*%#Comment#"
      .. name:gsub("%%", "%%%%")
      .. "%*%=%#Comment#"
      .. (selected and selected.running and "running " or "results ")
      .. "%*"
    if follow then vim.api.nvim_win_set_cursor(win, { #lines, 0 }) end
  end
end

local function poll()
  if polling or not visible() or not selected or not selected.running then return end
  polling = true
  vim.defer_fn(function()
    polling = false
    if not visible() then return end
    M.refresh()
    poll()
  end, 200)
end

function M.buffer()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "neotest-output"
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = false
    vim.keymap.set("n", "q", M.close, { buffer = buf, desc = "Close Test Output" })
  end
  return buf
end

function M.open(opts)
  opts = opts or {}
  local source = vim.api.nvim_get_current_win()
  if not visible() then
    local anchor = source
    if vim.bo[vim.api.nvim_win_get_buf(anchor)].filetype == "neotest-summary" then
      for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if
          vim.api.nvim_win_get_config(candidate).relative == ""
          and vim.bo[vim.api.nvim_win_get_buf(candidate)].filetype ~= "neotest-summary"
        then
          anchor = candidate
          break
        end
      end
    end
    vim.api.nvim_win_call(anchor, function()
      vim.cmd("belowright split")
      win = vim.api.nvim_get_current_win()
    end)
    vim.api.nvim_win_set_buf(win, M.buffer())
    vim.api.nvim_win_set_height(win, math.max(5, math.min(12, math.floor(vim.o.lines * 0.25))))
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].wrap = false
    vim.wo[win].winhighlight = "WinBar:Normal,WinBarNC:Normal"
  end
  M.refresh()
  poll()
  vim.api.nvim_set_current_win(opts.enter and win or source)
end

function M.close()
  if visible() then vim.api.nvim_win_close(win, false) end
  win = nil
end

function M.toggle()
  if visible() then
    M.close()
  else
    M.open()
  end
end

function M.clear()
  selected = nil
  M.refresh()
end

function M.show(opts)
  if type(opts) == "string" then opts = { position_id = opts } end
  opts = opts or {}
  local path, row = vim.api.nvim_buf_get_name(0), vim.api.nvim_win_get_cursor(0)[1] - 1
  require("nio").run(function()
    local tree, adapter
    local id = opts.position_id or opts[1]
    if id then
      tree, adapter = client:get_position(id, opts)
    else
      tree, adapter = client:get_nearest(path, row, opts)
    end
    if not tree then
      vim.notify(
        "No test selected. Open a test file or select a test in the tree.",
        vim.log.levels.WARN,
        { title = "Tests" }
      )
      return
    end
    for _, entry in pairs(active) do
      if entry.source == tree:data().path or vim.fs.relpath(entry.source, tree:data().path) then
        selected = entry
        M.open(opts)
        return
      end
    end
    if client:is_running(tree:data().id, { adapter = adapter }) then
      selected = { text = "Test process starting; waiting for output.", running = true }
      M.open(opts)
      return
    end
    local result
    local results = client:get_results(adapter)
    for _, position in tree:iter() do
      local candidate = results[position.id]
      if candidate and (candidate.output or candidate.short) then
        result = candidate
        if candidate.status == "failed" then break end
      end
    end
    if not result then
      vim.notify("No output yet for this test.", vim.log.levels.INFO, { title = "Tests" })
      return
    end
    selected = { file = not opts.short and result.output or nil, text = result.short, pinned = true }
    M.open(opts)
  end)
end

function M.attach(opts)
  opts = type(opts) == "string" and { position_id = opts } or vim.tbl_extend("force", opts or {}, { enter = true })
  M.show(opts)
end

function M.strategy(spec, context)
  spec.strategy = vim.tbl_extend("keep", spec.strategy or {}, require("neotest.config").strategies.integrated)
  local process = require("neotest.client.strategies.integrated")(spec)
  local entry = { file = process.output(), source = context.position.path, running = true }
  active[entry] = entry
  selected = entry
  vim.schedule(function()
    M.refresh()
    poll()
  end)
  local finish = process.result
  process.result = function()
    local result = finish()
    entry.running = false
    active[entry] = nil
    vim.schedule(M.refresh)
    return result
  end
  process.attach = function() M.attach({ position_id = context.position.id }) end
  return process
end

return setmetatable(M, {
  __call = function(_, neotest_client)
    client = neotest_client
    client.listeners.run = function(_, id)
      selected = { text = "Running tests: " .. id }
      vim.schedule(M.refresh)
    end
    client.listeners.results = function(adapter, results, partial)
      if selected and (selected.source or selected.pinned) then return end
      if selected and not partial then selected.running = false end
      local messages, files = {}, {}
      for id, result in pairs(results) do
        local position = client:get_position(id, { adapter = adapter })
        if position and position:data().type == "test" then
          messages[#messages + 1] = result.short or (position:data().name .. ": " .. result.status)
          for _, err in ipairs(result.errors or {}) do
            messages[#messages + 1] = err.message
          end
          if result.output and not files[result.output] then
            files[result.output] = true
            local output, err = read(result.output)
            messages[#messages + 1] = output or ("Cannot read test output: " .. tostring(err))
          end
        end
      end
      if #messages > 0 then
        selected = { text = table.concat(messages, "\n") }
        vim.schedule(M.refresh)
      end
    end
    return M
  end,
})
