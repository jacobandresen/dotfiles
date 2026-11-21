local M = {}

local excluded = {
  node_modules = true,
  bin = true,
  obj = true,
  dist = true,
  build = true,
  target = true,
  coverage = true,
  ["test-results"] = true,
  __pycache__ = true,
  venv = true,
  e2e = true,
  integration = true,
}

function M.filter_dir(name)
  return not excluded[name:lower()] and not name:match("^%.") and not name:lower():match("integrationtests$")
end

local function node_config(root, runner)
  for _, extension in ipairs({ "ts", "js", "mts", "mjs", "cts", "cjs" }) do
    local path = vim.fs.joinpath(root, runner .. ".config." .. extension)
    if vim.uv.fs_stat(path) then return path end
  end
end

function M.node_root(path, runner)
  local stat = vim.uv.fs_stat(path)
  local dir = stat and stat.type == "directory" and path or vim.fs.dirname(path)
  local package_root
  while dir do
    if node_config(dir, runner) then return dir end
    local manifest = vim.fs.joinpath(dir, "package.json")
    if not package_root and vim.uv.fs_stat(manifest) then
      local file = assert(io.open(manifest, "r"))
      local content = file:read("*a")
      file:close()
      local package = vim.json.decode(content)
      if (package.dependencies or {})[runner] or (package.devDependencies or {})[runner] or package[runner] then
        package_root = dir
      end
    end
    if vim.uv.fs_stat(vim.fs.joinpath(dir, ".git")) then break end
    local parent = vim.fs.dirname(dir)
    if parent == dir then break end
    dir = parent
  end
  return package_root
end

function M.node_adapter(runner)
  local function root(path) return M.node_root(path, runner) end
  local function config(path)
    local dir = assert(root(path), "No " .. runner .. " project for " .. path)
    return node_config(dir, runner) or (runner == "vitest" and node_config(dir, "vite") or nil)
  end
  local command_option = runner == "vitest" and "vitestCommand" or "jestCommand"
  local options = runner == "vitest" and { cwd = root, vitestConfigFile = config }
    or { cwd = root, jestConfigFile = config }
  options[command_option] = runner
  local adapter = require("neotest-" .. runner)(options)
  adapter.name = runner == "vitest" and "Vitest" or "Jest"
  adapter.root = root
  adapter.is_test_file = function(path)
    if not path then return false end
    local extension = path:match("%.([^.]+)$")
    if not vim.tbl_contains({ "js", "jsx", "ts", "tsx", "mjs", "cjs", "mts", "cts" }, extension) then return false end
    if not (path:match("[./]__tests__/") or path:match("%.test%.[^.]+$") or path:match("%.spec%.[^.]+$")) then
      return false
    end
    local project = root(path)
    if not project then return false end
    for component in vim.gsplit(vim.fs.relpath(project, path), "/", { plain = true, trimempty = true }) do
      if not M.filter_dir(component) then return false end
    end
    return true
  end
  local build_spec = adapter.build_spec
  adapter.build_spec = function(args)
    if args[command_option] then return build_spec(args) end
    local dir = assert(root(args.tree:data().path), "No " .. runner .. " project for this test")
    local binary
    while dir do
      local path = vim.fs.joinpath(dir, "node_modules", ".bin", runner)
      if vim.fn.executable(path) == 1 then
        binary = path
        break
      end
      if vim.uv.fs_stat(vim.fs.joinpath(dir, ".git")) then break end
      local parent = vim.fs.dirname(dir)
      if parent == dir then break end
      dir = parent
    end
    binary = binary or vim.fn.exepath(runner)
    assert(binary ~= "", "Install " .. runner .. " dependencies in this project before running tests")
    local spec = build_spec(args)
    if spec then
      -- Keep paths with spaces as one argv entry and never fall back to npx downloads.
      spec.command[1] = binary
      if type(spec.strategy) == "table" and spec.strategy.runtimeExecutable then
        spec.strategy.runtimeExecutable = binary
      end
    end
    return spec
  end
  return adapter
end

local dotnet_parser_configured = false
local summary_configured = false

function M.configure_summary()
  if summary_configured then return end
  local module = "neotest.consumers.summary.summary"
  local create = require(module)
  package.loaded[module] = function(client)
    local summary = create(client)
    local header = summary._write_header
    summary._write_header = function(self, canvas, adapter, tree)
      local first = canvas:length()
      header(self, canvas, adapter, tree)
      -- Native project headers have no run action, unlike their child rows.
      for row = first, canvas:length() - 1 do
        canvas:add_mapping(
          "run",
          function() require("neotest").run.run({ tree:data().path, adapter = adapter }) end,
          { line = row }
        )
        canvas:add_mapping(
          "stop",
          function() require("neotest").run.stop({ tree:data().path, adapter = adapter }) end,
          { line = row }
        )
      end
    end
    return summary
  end
  summary_configured = true
end

function M.configure_dotnet_parser()
  if dotnet_parser_configured then return end
  vim.treesitter.language.register("c_sharp", "cs")
  local adapter = require("neotest-dotnet")
  local build = adapter._build_position
  adapter._build_position = function(path, source, captured)
    local position = build(path, source, captured)
    local namespace = captured["namespace.definition"]
    if namespace and namespace:type() == "file_scoped_namespace_declaration" then
      -- Recent parsers give the namespace only its declaration's range, not the following classes.
      local root = namespace
      while root:parent() do
        root = root:parent()
      end
      local _, _, row, column = root:range()
      position.range[3], position.range[4] = row, column
    end
    return position
  end
  dotnet_parser_configured = true
end

function M.dotnet_adapter()
  local adapter = require("neotest-dotnet")({ discovery_root = "project" })
  adapter.name = ".NET"
  adapter.filter_dir = M.filter_dir
  local discover = adapter.discover_positions
  adapter.discover_positions = function(path)
    M.configure_dotnet_parser()
    local subprocess = require("neotest.lib").subprocess
    if subprocess.enabled() then
      local _, err = subprocess.call("require('util.testing').configure_dotnet_parser", {})
      assert(not err, "Cannot configure the C# test parser: " .. tostring(err))
    end
    return discover(path)
  end
  function adapter.build_spec(args)
    assert(args.strategy ~= "dap", "Use the project's existing DAP configuration to debug .NET tests")
    local groups = {}
    local utils = require("neotest-dotnet.utils.build-spec-utils")
    for _, position in args.tree:iter() do
      if position.type == "test" then
        local root = assert(adapter.root(position.path), "No C# project for " .. position.path)
        local group = groups[root] or {}
        groups[root] = group
        group[utils.build_test_fqn(position.running_id or position.id)] = true
      end
    end
    local specs = {}
    for root, tests in pairs(groups) do
      local projects = {}
      for name in vim.fs.dir(root) do
        if name:match("%.csproj$") then projects[#projects + 1] = vim.fs.joinpath(root, name) end
      end
      assert(#projects == 1, "Expected one C# project in " .. root)
      local global = vim.fs.find("global.json", { path = root, upward = true })[1]
      local platform = false
      if global then
        local file = assert(io.open(global, "r"))
        local content = file:read("*a")
        file:close()
        local config = vim.json.decode(content)
        platform = config.test and config.test.runner == "Microsoft.Testing.Platform"
      end
      local results = vim.fn.tempname() .. ".trx"
      local filters = {}
      for name in pairs(tests) do
        filters[#filters + 1] = "FullyQualifiedName=" .. name
      end
      table.sort(filters)
      local command = { "dotnet", "test" }
      if platform then
        vim.list_extend(command, {
          "--project",
          projects[1],
          "--report-trx",
          "--report-trx-filename",
          vim.fs.basename(results),
          "--results-directory",
          vim.fs.dirname(results),
          "--minimum-expected-tests",
          "1",
          "--no-ansi",
        })
      else
        vim.list_extend(command, {
          projects[1],
          "--logger",
          "trx;LogFileName=" .. vim.fs.basename(results),
          "--results-directory",
          vim.fs.dirname(results),
        })
      end
      vim.list_extend(command, { "--filter", table.concat(filters, "|") })
      vim.list_extend(command, args.extra_args or {})
      specs[#specs + 1] = {
        command = command,
        cwd = root,
        context = { results_path = results, file = args.tree:data().path, id = args.tree:data().id },
      }
    end
    return specs
  end
  local solution = require("neotest.lib").files.match_root_pattern("*.sln", "*.slnx")
  local project = adapter.root
  return vim.tbl_extend("force", adapter, {
    root = function(path) return solution(path) or project(path) end,
  })
end

function M.open_summary()
  require("util.sidebars").keep("tests")
  vim.cmd("topleft vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, math.max(24, math.min(38, math.floor(vim.o.columns * 0.26))))
  vim.wo[win].winfixwidth = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].winbar = "%#Title# Tests %*%=%#Comment#? help %*"
  vim.wo[win].winhighlight = "Normal:NormalFloat,NormalNC:NormalFloat,WinBar:NormalFloat,WinBarNC:NormalFloat"
  return win
end

function M.open_view(root, refresh)
  root = root or vim.fn.getcwd()
  if require("util.sidebars").keep("tests") then
    local source = vim.api.nvim_get_current_win()
    -- Snacks closes its windows on the next tick; build the new layout afterward.
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(source) then
        vim.api.nvim_win_call(source, function() M.open_view(root, refresh) end)
      end
    end)
    return
  end
  local win = vim.api.nvim_get_current_win()
  local neotest = require("neotest")
  neotest.summary.open()
  neotest.output_panel.open()
  neotest.test_workspace.discover(root, refresh)
  if vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) end
end

function M.toggle_view()
  local neotest = require("neotest")
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neotest-summary" then
      neotest.summary.close()
      neotest.output_panel.close()
      return
    end
  end
  M.open_view()
end

local function adapter_for_path(path)
  local state = require("neotest").state
  for _, adapter in ipairs(state.adapter_ids()) do
    local positions = state.positions(adapter)
    if positions and positions:get_key(path) then return adapter end
  end
end

function M.run_file()
  local path = vim.api.nvim_buf_get_name(0)
  local adapter = adapter_for_path(path)
  M.open_view()
  require("neotest").run.run({ path, adapter = adapter })
end

function M.run_nearest()
  local adapter = adapter_for_path(vim.api.nvim_buf_get_name(0))
  M.open_view()
  require("neotest").run.run({ adapter = adapter })
end

function M.run_directory()
  local path = vim.fn.expand("%:p:h")
  local adapter = adapter_for_path(vim.api.nvim_buf_get_name(0))
  M.open_view()
  require("neotest").run.run({ path, adapter = adapter })
end

function M.statusline()
  local neotest = package.loaded.neotest
  if not neotest or not package.loaded["neotest.consumers.state"] then return "" end
  local counts = { running = 0, failed = 0, passed = 0 }
  for _, adapter in ipairs(neotest.state.adapter_ids()) do
    local state = neotest.state.status_counts(adapter)
    if state then
      for status in pairs(counts) do
        counts[status] = counts[status] + state[status]
      end
    end
  end
  local parts = {}
  for _, status in ipairs({ "running", "failed", "passed" }) do
    if counts[status] > 0 then parts[#parts + 1] = counts[status] .. " " .. status end
  end
  return #parts > 0 and "Tests: " .. table.concat(parts, " / ") or ""
end

function M.rust_adapter()
  local adapter = require("rustaceanvim.neotest")
  local discover = adapter.discover_positions
  local ra = require("rustaceanvim.rust_analyzer")
  local get_client = ra.get_client_for_file
  ra.get_client_for_file = function(path, method)
    local server = get_client(path, method)
    if server then return server end
    for _, candidate in ipairs(ra.get_active_rustaceanvim_clients(nil, { method = method })) do
      for _, folder in ipairs(candidate.workspace_folders or {}) do
        if vim.fs.relpath(vim.uri_to_fname(folder.uri), path) then return candidate end
      end
    end
  end
  local ready = {}
  local method = "experimental/serverStatus"
  local handlers = (vim.lsp.config["rust-analyzer"] or {}).handlers or {}
  local status = handlers[method] or require("rustaceanvim.server_status").handler
  vim.lsp.config("rust-analyzer", {
    handlers = {
      [method] = function(err, result, context, opts)
        if result then ready[context.client_id] = result.quiescent end
        status(err, result, context, opts)
      end,
    },
  })
  return vim.tbl_extend("force", adapter, {
    filter_dir = M.filter_dir,
    discover_positions = function(path)
      require("nio").scheduler()
      local server = ra.get_client_for_file(path, "experimental/runnables")
      local starting = not server or not server.initialized or ready[server.id] == false
      if not server then
        for _, candidate in ipairs(ra.get_active_rustaceanvim_clients()) do
          ready[candidate.id] = false
        end
        local buf = vim.fn.bufadd(path)
        vim.fn.bufload(buf)
        vim.bo[buf].filetype = "rust"
        require("rustaceanvim.lsp").start(buf)
      end
      local deadline = vim.uv.hrtime() + 30 * 1000000000
      repeat
        require("nio").scheduler()
        server = ra.get_client_for_file(path, "experimental/runnables")
        if server and server.initialized and (not starting or ready[server.id]) then break end
        assert(vim.uv.hrtime() < deadline, "Rust test discovery timed out waiting for rust-analyzer: " .. path)
        require("nio").sleep(100)
      until false
      return discover(path)
    end,
  })
end

return M
