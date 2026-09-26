-- The Turbo Pascal 7.0 menu tree, limited to the TP entries that have a
-- working Neovim equivalent. Docker and AI are Tools transfer items (TP7
-- listed extra programs there); anything else TP never had (databases,
-- git) is a <leader> keymap only (which-key).
local chrome = require("turbo.chrome")

local function cmd(c)
  return function() vim.cmd(c) end
end

local function feed(keys)
  return function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "m", false)
  end
end

local function dap(fn)
  return function() require("dap")[fn]() end
end

-- dap-ui is set up in nvim-dap's config (plugins/dap.lua), so load dap first
local function dapui()
  require("dap")
  return require("dapui")
end

local function dapui_float(element)
  return function() dapui().float_element(element, { enter = true }) end
end

-- the selection when the menu was opened from Visual mode, else the line
local function range(ctx)
  return ctx.visual and "'<,'>" or ""
end

local function cc()
  return require("codecompanion")
end

-- quickfix navigation that says so instead of failing with E42/E553
local function qf(c)
  return function()
    if #vim.fn.getqflist() == 0 then
      return vim.notify("No messages")
    end
    pcall(vim.cmd, c)
  end
end

local function pick(name, opts)
  return function() LazyVim.pick(name, opts)() end
end

local function telescope(name, opts)
  return function() require("telescope.builtin")[name](opts or {}) end
end

-- default may be a function, evaluated when the item is chosen
local function input(prompt, default, completion, fn)
  return function()
    if type(default) == "function" then
      default = default()
    end
    vim.ui.input({ prompt = prompt, default = default, completion = completion }, function(value)
      if value and value ~= "" then
        fn(value)
      end
    end)
  end
end

local function edit(visual_keys, line_keys)
  return function(ctx)
    vim.cmd("normal! " .. (ctx.visual and ("gv" .. visual_keys) or line_keys))
  end
end

-- :make with the filetype's makeprg (Rust: cargo build). Errors open the
-- Messages (quickfix) window, success says so.
local function make()
  return function()
    vim.cmd("silent! wall")
    local target = vim.bo.makeprg:match("^cargo") and "build" or ""
    vim.cmd("silent make " .. target)
    local errors = #vim.tbl_filter(function(e) return e.valid == 1 end, vim.fn.getqflist())
    if vim.v.shell_error ~= 0 or errors > 0 then
      vim.cmd("copen")
      vim.notify(("Make failed: %d error(s)"):format(errors), vim.log.levels.ERROR)
    else
      vim.notify("Make succeeded")
    end
  end
end

local M = {}

M.make = make()
M.qf = qf

-- lazydocker in the same window style as lazygit (title, Alt+X to close)
function M.lazydocker()
  Snacks.terminal("lazydocker", { win = { style = "lazygit", title = " Lazydocker " } })
end

M.docker = {
  { label = "~E~xplorer", key = "Space g C", hint = "Containers, images, volumes and networks: start, stop, logs, shell",
    action = function() require("util.compose").open() end },
  { label = "~L~ogs...", key = "Space g O", hint = "Open the log of a compose service or container in a buffer",
    action = function() require("util.compose.logs").pick() end },
  "-",
  { label = "Lazy~d~ocker", key = "Space g d", hint = "Docker UI in a terminal window", action = M.lazydocker },
}

M.ai = {
  { label = "~C~hat window", key = "Space a c", hint = "Show or hide the CodeCompanion chat", action = function() cc().toggle() end },
  { label = "~N~ew chat (Ollama)", key = "Space a n", hint = "Start a chat with the loaded Ollama model",
    action = function() cc().chat({ params = { adapter = "ollama" } }) end },
  { label = "~A~dd to chat", key = "Space a p", hint = "Send the block (or line) to the chat",
    action = function(ctx) vim.cmd(range(ctx) .. "CodeCompanionChat Add") end },
  "-",
  { label = "~I~nline edit...", key = "Space a i", hint = "Ask the AI to edit the block (or file) in place",
    action = function(ctx) vim.cmd(range(ctx) .. "CodeCompanion") end },
  { label = "Ac~t~ion palette...", key = "Space a a", hint = "Explain, fix, write tests...",
    action = function(ctx) vim.cmd(range(ctx) .. "CodeCompanionActions") end },
  "-",
  { label = "~S~aved chats...", key = "Space a s", hint = "Restore a saved chat session", action = function() cc().sessions() end },
  { label = "~E~dited files", key = "Space a e", hint = "Files the AI changed, in the quickfix list", action = function() cc().changes() end },
  { label = "C~h~ange adapter...", key = "Space a A", hint = "Switch the open chat between Ollama and Copilot", action = feed("<leader>aA") },
  "-",
  { label = "~G~host text", key = "Space a g", hint = "Toggle Minuet's inline suggestions in this buffer",
    action = function() require("minuet") vim.cmd("Minuet virtualtext toggle") end },
}

M.db = {
  { label = "~T~oggle database UI", key = "Space D u", hint = "Show or hide the Dadbod connections drawer", action = cmd("DBUIToggle") },
  { label = "~A~dd connection...", key = "Space D a", hint = "Add a database connection URL", action = cmd("DBUIAddConnection") },
  { label = "~F~ind buffer", key = "Space D f", hint = "Show this query buffer in the drawer", action = require("util.db").in_query("DBUIFindBuffer") },
  "-",
  { label = "~E~xecute query", key = "Space D e", hint = "Run the block (or whole buffer) against the buffer's database",
    action = function(ctx) require("util.db").execute(ctx.visual and "'<,'>" or "%") end },
  { label = "~R~ename buffer...", key = "Space D r", hint = "Rename the current query buffer", action = require("util.db").in_query("DBUIRenameBuffer") },
  { label = "Last query ~i~nfo", key = "Space D i", hint = "Show timing and details of the last query", action = cmd("DBUILastQueryInfo") },
}

M.menus = {
  {
    title = "≡",
    items = {
      { label = "~R~epaint desktop", hint = "Redraw the screen", action = cmd("mode") },
    },
  },
  {
    title = "~F~ile",
    items = function()
      local items = {
        { label = "~N~ew", hint = "Create a new empty buffer", action = cmd("enew") },
        { label = "~O~pen...", key = "F3", hint = "Find and open a file", action = pick("files") },
        { label = "~S~ave", key = "F2", hint = "Save the file in the active window", action = cmd("write") },
        { label = "Save ~a~s...", hint = "Save the file under a new name",
          action = input("Save as: ", function() return vim.fn.expand("%") end, "file", function(v) vim.cmd.saveas(v) end) },
        { label = "Save a~l~l", hint = "Save all modified files", action = cmd("wall") },
        "-",
        { label = "E~x~it", key = "Alt+X", hint = "Quit Turbo Vim", action = cmd("confirm qall") },
      }
      -- TP listed recently opened files at the bottom of the File menu
      local recent = {}
      for _, f in ipairs(vim.v.oldfiles) do
        if #recent == 3 then
          break
        end
        if vim.fn.filereadable(f) == 1 and not f:match("^/tmp/") then
          table.insert(recent, f)
        end
      end
      if #recent > 0 then
        table.insert(items, "-")
        for i, f in ipairs(recent) do
          local dir = vim.fn.fnamemodify(f, ":~:.:h")
          table.insert(items, {
            label = ("~%d~ %s"):format(i, vim.fn.fnamemodify(f, ":t")),
            key = #dir > 24 and vim.fn.pathshorten(dir, 3) or dir,
            hint = "Reopen " .. vim.fn.fnamemodify(f, ":~"),
            action = function() vim.cmd.edit(vim.fn.fnameescape(f)) end,
          })
        end
      end
      return items
    end,
  },
  {
    title = "~E~dit",
    items = {
      { label = "~U~ndo", key = "Alt+BkSp", hint = "Undo the last change", action = cmd("undo") },
      { label = "~R~edo", key = "Ctrl+R", hint = "Redo the last undone change", action = cmd("redo") },
      "-",
      { label = "Cu~t~", key = "Shift+Del", hint = "Cut the block (or line) to the clipboard", action = edit('"+d', '"+dd') },
      { label = "~C~opy", key = "Ctrl+Ins", hint = "Copy the block (or line) to the clipboard", action = edit('"+y', '"+yy') },
      { label = "~P~aste", key = "Shift+Ins", hint = "Insert the clipboard at the cursor", action = edit('"+p', '"+P') },
      { label = "C~l~ear", key = "Ctrl+Del", hint = "Delete the block (or line) without copying it", action = edit('"_d', '"_dd') },
      "-",
      { label = "~S~how clipboard", hint = "Browse the registers", action = telescope("registers") },
    },
  },
  {
    title = "~S~earch",
    items = {
      { label = "~F~ind...", key = "/", hint = "Search forward in this file", action = feed("/") },
      { label = "~R~eplace...", key = "Space s r", hint = "Search and replace (grug-far)",
        action = function(ctx)
          local grug = require("grug-far")
          if ctx.visual then
            grug.with_visual_selection()
          else
            grug.open({ prefills = { search = vim.fn.expand("<cword>") } })
          end
        end },
      { label = "~S~earch again", key = "n", hint = "Repeat the last search",
        action = function()
          if vim.fn.getreg("/") == "" then
            return vim.notify("No previous search")
          end
          pcall(vim.cmd, "normal! n")
        end },
      "-",
      { label = "~G~o to line number...", hint = "Jump to a line in this file",
        action = input("Line number: ", nil, nil, function(v) vim.cmd(tostring(tonumber(v) or 1)) end) },
      { label = "Show ~l~ast compiler error", hint = "Jump to the current compiler message", action = qf("cc") },
      { label = "Find ~e~rror...", key = "Space s d", hint = "List the diagnostics in this file", action = telescope("diagnostics", { bufnr = 0 }) },
      { label = "Find ~p~rocedure...", key = "Space s s", hint = "Jump to a symbol in this file", action = telescope("lsp_document_symbols") },
      "-",
      { label = "Glo~b~als", key = "Space s S", hint = "Symbols across the workspace", action = telescope("lsp_dynamic_workspace_symbols") },
      { label = "S~y~mbol...", key = "g r", hint = "Find references to the symbol under the cursor", action = telescope("lsp_references") },
    },
  },
  {
    title = "~R~un",
    items = {
      { label = "~R~un", key = "Ctrl+F9", hint = "Start or continue debugging", action = dap("continue") },
      { label = "~S~tep over", key = "F8", hint = "Execute the next line, stepping over calls", action = dap("step_over") },
      { label = "~T~race into", key = "F7", hint = "Execute the next line, stepping into calls", action = dap("step_into") },
      { label = "~G~o to cursor", key = "F4", hint = "Run until the cursor line", action = dap("run_to_cursor") },
      { label = "~P~rogram reset", key = "Ctrl+F2", hint = "Stop the debug session", action = dap("terminate") },
    },
  },
  {
    title = "~C~ompile",
    items = {
      { label = "~M~ake", key = "F9", hint = "Save all and run :make (Rust: cargo build)", action = M.make },
    },
  },
  {
    title = "~D~ebug",
    items = {
      { label = "~B~reakpoints...", hint = "List all breakpoints",
        action = function() require("dap").list_breakpoints() vim.cmd("copen") end },
      { label = "~C~all stack", key = "Ctrl+F3", hint = "Show the call stack", action = dapui_float("stacks") },
      { label = "~W~atch", hint = "Show the watches", action = dapui_float("watches") },
      { label = "~O~utput", hint = "Show the program output", action = dapui_float("console") },
      { label = "~U~ser screen", key = "Alt+F5", hint = "Toggle the debugger panels", action = function() dapui().toggle() end },
      "-",
      { label = "~E~valuate/modify...", key = "Ctrl+F4", hint = "Evaluate the expression under the cursor",
        action = function() dapui().eval(nil, { enter = true }) end },
      { label = "~A~dd watch...", key = "Ctrl+F7", hint = "Watch an expression",
        action = input("Add watch: ", function() return vim.fn.expand("<cword>") end, nil, function(v) dapui().elements.watches.add(v) end) },
      { label = "Add brea~k~point...", hint = "Add a conditional breakpoint on this line",
        action = input("Condition: ", nil, nil, function(v) require("dap").set_breakpoint(v) end) },
    },
  },
  {
    title = "~T~ools",
    items = {
      { label = "~M~essages", hint = "Open the quickfix list", action = cmd("copen") },
      { label = "Go to ~n~ext", key = "Alt+F8", hint = "Next compiler message", action = qf("cnext") },
      { label = "Go to ~p~revious", key = "Alt+F7", hint = "Previous compiler message", action = qf("cprevious") },
      "-",
      { label = "~G~rep", key = "Shift+F2", hint = "Search the project with ripgrep", action = pick("live_grep") },
      -- transfer items (TP's Options > Tools), as cascading submenus
      "-",
      { label = "~D~ocker", hint = "Docker explorer, logs and Lazydocker", items = M.docker },
      { label = "~A~I", hint = "CodeCompanion chat and inline edits, Minuet ghost text", items = M.ai },
      { label = "Data~b~ase", hint = "Dadbod database UI and queries", items = M.db },
    },
  },
  {
    title = "~O~ptions",
    items = {
      { label = "~C~ompiler...", hint = "Language servers attached to this file", action = function() Snacks.picker.lsp_config() end },
      { label = "~D~irectories...", key = "Space f c", hint = "Browse the Turbo Vim config directory",
        action = pick("files", { cwd = vim.fn.stdpath("config") }) },
      { label = "~T~ools...", hint = "Language servers, debuggers and formatters (:Mason)", action = cmd("Mason") },
      { label = "~E~nvironment...", hint = "Browse and change editor options", action = telescope("vim_options") },
      "-",
      { label = "~O~pen...", key = "Space q S", hint = "Restore a saved session", action = function() require("persistence").select() end },
    },
  },
  {
    title = "~W~indow",
    items = {
      { label = "~T~ile", key = "Ctrl+W =", hint = "Make all windows the same size", action = cmd("wincmd =") },
      { label = "Cl~o~se all", hint = "Close all files", action = function() Snacks.bufdelete.all() end },
      "-",
      { label = "~Z~oom", key = "F5", hint = "Maximise the active window", action = function() Snacks.zen.zoom() end },
      { label = "~N~ext", key = "F6", hint = "Go to the next window", action = cmd("wincmd w") },
      { label = "~P~revious", key = "Shift+F6", hint = "Go to the previous window", action = cmd("wincmd W") },
      { label = "~C~lose", key = "Alt+F3", hint = "Close the active file", action = function() Snacks.bufdelete() end },
      "-",
      { label = "~L~ist...", key = "Alt+0", hint = "Pick an open file", action = telescope("buffers", { sort_mru = true }) },
    },
  },
  {
    title = "~H~elp",
    items = {
      { label = "~C~ontents", key = "F1", hint = "Open the Neovim manual", action = cmd("help") },
      { label = "~I~ndex", key = "Shift+F1", hint = "Search all help topics", action = telescope("help_tags") },
      { label = "~T~opic search", key = "Ctrl+F1", hint = "Help for the word under the cursor",
        action = function() pcall(vim.cmd.help, vim.fn.expand("<cword>")) end },
      { label = "~U~sing help", hint = "How to use the help", action = cmd("help help") },
      { label = "~E~rror messages", hint = "Neovim error messages", action = cmd("help error-messages") },
      "-",
      { label = "~A~bout...", hint = "Show version and copyright information", action = chrome.about },
    },
  },
}

-- TP's edit-window local menu (Alt+F10 / right click)
M.local_menu = {
  { label = "~V~iew / Edit markdown", key = "Space u m", hint = "Switch between the rendered view and the source",
    when = function() return vim.bo.filetype == "markdown" end,
    action = function() require("util.mdview").toggle() end },
  { "-", when = function() return vim.bo.filetype == "markdown" end },
  { label = "Cu~t~", key = "Shift+Del", hint = "Cut the block (or line) to the clipboard", action = edit('"+d', '"+dd') },
  { label = "~C~opy", key = "Ctrl+Ins", hint = "Copy the block (or line) to the clipboard", action = edit('"+y', '"+yy') },
  { label = "~P~aste", key = "Shift+Ins", hint = "Insert the clipboard at the cursor", action = edit('"+p', '"+P') },
  "-",
  { label = "~O~pen file at cursor", key = "g f", hint = "Edit the file whose name is under the cursor",
    action = function()
      local name = vim.fn.expand("<cfile>")
      if name == "" then
        return vim.notify("No file name under the cursor", vim.log.levels.WARN)
      end
      if not pcall(vim.cmd, "normal! gf") then
        vim.notify("File not found: " .. name, vim.log.levels.WARN)
      end
    end },
  { label = "Topic ~s~earch", key = "Ctrl+F1", hint = "Help for the word under the cursor",
    action = function() pcall(vim.cmd.help, vim.fn.expand("<cword>")) end },
  { label = "Bro~w~se symbol at cursor", key = "g d", hint = "Go to the definition of the symbol under the cursor",
    action = function() vim.lsp.buf.definition() end },
  "-",
  { label = "~G~o to cursor", key = "F4", hint = "Run until the cursor line", action = dap("run_to_cursor") },
  { label = "Toggle ~b~reakpoint", key = "Ctrl+F8", hint = "Set or clear a breakpoint on this line", action = dap("toggle_breakpoint") },
  { label = "~E~valuate/modify...", key = "Ctrl+F4", hint = "Evaluate the expression under the cursor",
    action = function() dapui().eval(nil, { enter = true }) end },
  { label = "~A~dd watch...", key = "Ctrl+F7", hint = "Watch an expression",
    action = input("Add watch: ", function() return vim.fn.expand("<cword>") end, nil, function(v) dapui().elements.watches.add(v) end) },
  "-",
  { label = "~I~nline AI edit...", key = "Space a i", hint = "Ask the AI to edit the block (or line) in place",
    action = function(ctx) vim.cmd(range(ctx) .. "CodeCompanion") end },
}

return M
