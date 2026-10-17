-- Adapters/configurations for C, C++ and Rust (codelldb) and JS/TS
-- (js-debug) live here; C# is handled by nvim-dap-cs below.
local mason = vim.fn.stdpath("data") .. "/mason"

local function evaluate()
  local mode = vim.fn.mode()
  if not mode:match("^[vV\22]") then
    return require("dapui").eval(nil, { enter = true })
  end
  vim.cmd("normal! \27")
  local expression = table.concat(vim.fn.getregion(vim.fn.getpos("'<"), vim.fn.getpos("'>"), {
    type = mode,
    exclusive = vim.o.selection == "exclusive",
  }), "\n")
  if expression ~= "" then require("dapui").eval(expression, { enter = true }) end
end

local function add_watch()
  vim.ui.input({ prompt = "Add watch: ", default = vim.fn.expand("<cword>") }, function(value)
    if value and value ~= "" then require("dapui").elements.watches.add(value) end
  end)
end

local function lldb_launch(name, dir)
  return {
    name = name,
    type = "codelldb",
    request = "launch",
    program = function()
      return vim.fn.input("Executable: ", vim.fn.getcwd() .. dir, "file")
    end,
    cwd = "${workspaceFolder}",
    stopOnEntry = false,
  }
end

local lldb_attach = {
  name = "Attach to process",
  type = "codelldb",
  request = "attach",
  pid = function() return require("dap.utils").pick_process() end,
  cwd = "${workspaceFolder}",
}

return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      { "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" } },
    },
    keys = {
      { "<F4>",   function() require("dap").run_to_cursor() end,         desc = "Run to Cursor" },
      { "<S-F4>", evaluate, desc = "Evaluate", mode = { "n", "v" } },
      { "<F5>",   function() require("dap").toggle_breakpoint() end,     desc = "Toggle Breakpoint" },
      { "<S-F5>", function() require("dap").terminate() end,             desc = "Stop" },
      { "<F7>",   function() require("dap").step_into() end,             desc = "Step Into" },
      { "<S-F7>", add_watch, desc = "Add Watch" },
      { "<F8>",   function() require("dap").step_over() end,             desc = "Step Over" },
      { "<S-F8>", function() require("dap").step_out() end,              desc = "Step Out" },
      { "<S-F9>", function() require("dap").continue() end,              desc = "Start / Continue" },

      -- Breakpoints
      { "<leader>db",  function() require("dap").toggle_breakpoint() end, desc = "Toggle Breakpoint" },
      { "<leader>dB",  function() require("dap").set_breakpoint(vim.fn.input("Condition: ")) end, desc = "Conditional Breakpoint" },
      { "<leader>dl",  function() require("dap").set_breakpoint(nil, nil, vim.fn.input("Log: ")) end, desc = "Logpoint" },
      { "<leader>dC",  function() require("dap").clear_breakpoints() end, desc = "Clear Breakpoints" },

      -- Session / UI
      { "<leader>dr",  function() require("dap").restart() end,          desc = "Restart" },
      { "<leader>du",  function() require("dapui").toggle() end,         desc = "Toggle UI" },
      { "<leader>ds",  function() require("dapui").float_element("stacks", { enter = true }) end, desc = "Call Stack" },
      { "<leader>de",  evaluate, desc = "Eval", mode = { "n", "v" } },
      { "<leader>dR",  function() require("dap").repl.open() end,        desc = "REPL" },
    },
    config = function()
      local dap, dapui = require("dap"), require("dapui")
      dapui.setup()

      dap.listeners.after.event_initialized["dapui_config"] = function() dapui.open() end
      dap.listeners.before.event_terminated["dapui_config"] = function() dapui.close() end
      dap.listeners.before.event_exited["dapui_config"] = function() dapui.close() end

      dap.adapters.codelldb = {
        type = "server",
        port = "${port}",
        executable = { command = mason .. "/bin/codelldb", args = { "--port", "${port}" } },
      }
      dap.configurations.c = { lldb_launch("Launch", "/"), lldb_attach }
      dap.configurations.cpp = dap.configurations.c
      dap.configurations.rust = {
        lldb_launch("Launch binary", "/target/debug/"),
        lldb_launch("Launch binary (release)", "/target/release/"),
        lldb_attach,
      }

      -- js-debug's DAP server, as installed by Mason
      for _, adapter in ipairs({ "pwa-node", "pwa-chrome" }) do
        dap.adapters[adapter] = {
          type = "server",
          host = "localhost",
          port = "${port}",
          executable = {
            command = "node",
            args = { mason .. "/packages/js-debug-adapter/js-debug/src/dapDebugServer.js", "${port}" },
          },
        }
      end
      local js_config = {
        {
          name = "Launch file",
          type = "pwa-node",
          request = "launch",
          program = "${file}",
          cwd = "${workspaceFolder}",
          sourceMaps = true,
          resolveSourceMapLocations = { "${workspaceFolder}/**", "!**/node_modules/**" },
        },
        {
          name = "Attach",
          type = "pwa-node",
          request = "attach",
          processId = function() return require("dap.utils").pick_process() end,
          cwd = "${workspaceFolder}",
          sourceMaps = true,
        },
        {
          name = "Launch Chrome",
          type = "pwa-chrome",
          request = "launch",
          url = function()
            return vim.fn.input("URL: ", "http://localhost:3000")
          end,
          webRoot = "${workspaceFolder}",
          sourceMaps = true,
        },
      }
      for _, lang in ipairs({ "javascript", "typescript", "javascriptreact", "typescriptreact" }) do
        dap.configurations[lang] = js_config
      end
    end,
  },

  {
    "NicholasMata/nvim-dap-cs",
    dependencies = { "mfussenegger/nvim-dap" },
    ft = { "cs" },
    config = function()
      require("dap-cs").setup({
        dap_configurations = {
          {
            type = "coreclr",
            name = "Launch",
            request = "launch",
            program = function()
              return vim.fn.input("Path to dll: ", vim.fn.getcwd() .. "/bin/Debug/", "file")
            end,
            cwd = "${workspaceFolder}",
            stopAtEntry = false,
          },
          {
            type = "coreclr",
            name = "Attach to process",
            request = "attach",
          },
        },
        netcoredbg = {
          path = mason .. "/bin/netcoredbg",
        },
      })
    end,
  },
}
