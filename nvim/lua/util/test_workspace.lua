local M = {}
local client
local scanned, scanning = {}, {}
local batches = {}

function M.is_complete(root)
  root = vim.fs.normalize(vim.fn.fnamemodify(root, ":p"))
  return scanned[root] == true and not scanning[root]
end

function M.find_tests(root)
  local nio = require("nio")
  local directories, tests = { root }, {}
  local adapters = require("neotest.config").adapters
  while #directories > 0 do
    local dir = table.remove(directories)
    local err, scan = nio.uv.fs_scandir(dir)
    assert(scan, "Cannot discover test projects in " .. dir .. ": " .. tostring(err))
    nio.scheduler()
    while true do
      local name, kind = vim.uv.fs_scandir_next(scan)
      if not name then break end
      if kind == "directory" and require("util.testing").filter_dir(name) then
        directories[#directories + 1] = vim.fs.joinpath(dir, name)
      elseif kind == "file" then
        local path = vim.fs.joinpath(dir, name)
        for _, adapter in ipairs(adapters) do
          nio.scheduler()
          if adapter.is_test_file(path) then
            nio.scheduler()
            local project = adapter.root(path) or dir
            local key = adapter.name .. ":" .. project
            if not tests[key] then tests[key] = path end
          end
        end
      end
    end
  end
  local paths = vim.tbl_values(tests)
  table.sort(paths)
  return paths
end

function M.discover(root, refresh)
  root = vim.fs.normalize(vim.fn.fnamemodify(root, ":p"))
  if scanning[root] or (scanned[root] and not refresh) then return end
  scanning[root] = true
  require("nio").run(function()
    local ok, err = xpcall(function()
      -- A file selects its language adapter; a directory can match an unrelated parent adapter.
      for _, path in ipairs(M.find_tests(root)) do
        client:get_position(path)
      end
      scanned[root] = true
    end, debug.traceback)
    scanning[root] = nil
    if not ok then vim.schedule(function() vim.notify(err, vim.log.levels.ERROR, { title = "Test discovery" }) end) end
  end)
end

function M.directory_runs(path)
  local runs = {}
  local state = require("neotest").state
  for _, adapter in ipairs(state.adapter_ids()) do
    local tree = state.positions(adapter)
    if tree then
      local node = tree:get_key(path)
      if not node and vim.fs.relpath(path, tree:data().path) then node = tree end
      if node then
        for _, position in node:iter() do
          if position.type == "test" then
            runs[#runs + 1] = { node:data().id, adapter = adapter }
            break
          end
        end
      end
    end
  end
  table.sort(runs, function(a, b) return a.adapter < b.adapter end)
  return runs
end

function M.run_directory(path, args, run)
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  if batches[path] then
    vim.notify("Tests are already running for " .. path, vim.log.levels.WARN, { title = "Tests" })
    return
  end
  local batch = { cancelled = false }
  batches[path] = batch
  return require("nio").run(function()
    require("nio").scheduler()
    M.discover(path)
    while scanning[path] do
      require("nio").sleep(50)
      require("nio").scheduler()
    end
    if not scanned[path] then return end
    local runs = M.directory_runs(path)
    if #runs == 0 then
      vim.notify("No unit tests discovered in " .. path, vim.log.levels.WARN, { title = "Tests" })
      return
    end
    for _, selection in ipairs(runs) do
      if batch.cancelled then break end
      run(vim.tbl_extend("force", args, selection))
    end
  end, function(ok, err)
    batches[path] = nil
    if not ok then vim.schedule(function() vim.notify(err, vim.log.levels.ERROR, { title = "Tests" }) end) end
  end)
end

function M.stop_directory(path)
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  for root, batch in pairs(batches) do
    if vim.fs.relpath(path, root) then batch.cancelled = true end
  end
  require("nio").run(function()
    for _, selection in ipairs(M.directory_runs(path)) do
      local tree = client:get_position(selection[1], { adapter = selection.adapter })
      if tree then
        for _, position in tree:iter() do
          if position.type == "test" and client:is_running(position.id, { adapter = selection.adapter }) then
            client:stop(tree:get_key(position.id), { adapter = selection.adapter })
          end
        end
      end
    end
  end)
end

return setmetatable(M, {
  __call = function(_, neotest_client)
    client = neotest_client
    return M
  end,
})
