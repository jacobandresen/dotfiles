-- The menu tree, grouped by task (File, Edit, Search, Code, Build, Debug, AI,
-- Tools, Window, Help) with cascading submenus; Turbo Vision look, but not
-- TP7's menu names. Every item that shows a key has that key as a keymap too,
-- and no key is one GNOME or KDE takes first (see turbo/init.lua).
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

-- ]q / [q: Trouble's list when it's open, else the compiler messages
function M.messages(dir)
  return function()
    if package.loaded.trouble and require("trouble").is_open() then
      return require("trouble")[dir]({ skip_groups = true, jump = true })
    end
    qf(dir == "next" and "cnext" or "cprevious")()
  end
end

function M.topic_search()
  local word = vim.fn.expand("<cword>")
  if word == "" or not pcall(vim.cmd.help, word) then
    vim.notify(word == "" and "No word under the cursor" or ("No help for " .. word), vim.log.levels.WARN)
  end
end

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
  { label = "Edit ~c~onnections...", key = "Space D c", hint = "Edit the saved connections file (~/.local/share/nvim/db_ui, not in git)",
    action = function() require("util.db").edit_connections() end },
  { label = "~F~ind buffer", key = "Space D f", hint = "Show this query buffer in the drawer", action = require("util.db").in_query("DBUIFindBuffer") },
  "-",
  { label = "~E~xecute query", key = "Space D e", hint = "Run the block (or whole buffer) against the buffer's database",
    action = function(ctx) require("util.db").execute(ctx.visual and "'<,'>" or "%") end },
  { label = "~R~ename buffer...", key = "Space D r", hint = "Rename the current query buffer", action = require("util.db").in_query("DBUIRenameBuffer") },
  { label = "Last query ~i~nfo", key = "Space D i", hint = "Show timing and details of the last query", action = cmd("DBUILastQueryInfo") },
}

-- git pickers outside a repository fail with a raw command dump; say it plainly
local function git(fn)
  return function()
    if not vim.fs.root(0, ".git") and not vim.fs.root(vim.fn.getcwd(), ".git") then
      return vim.notify("Not a git repository", vim.log.levels.WARN)
    end
    fn()
  end
end

M.git = {
  { label = "~L~azygit", key = "Space g g", hint = "Git UI in a terminal window", action = function() Snacks.lazygit() end },
  { label = "L~o~g", key = "Space g l", hint = "Commits of this repository", action = git(function() Snacks.picker.git_log({ cwd = LazyVim.root.git() }) end) },
  { label = "~D~iff", hint = "Changed hunks in the working tree", action = git(function() Snacks.picker.git_diff() end) },
  { label = "~B~lame line", key = "Space g b", hint = "Commits that changed the line under the cursor",
    action = git(function() Snacks.picker.git_log_line() end) },
}

-- Edit > Transform: one item per util/transform.lua transformation
local function transforms()
  local items, used = {}, {}
  for i, t in ipairs(require("util.transform").transformations) do
    if i > 1 and t.name:match("^%S+") ~= require("util.transform").transformations[i - 1].name:match("^%S+") then
      table.insert(items, "-")
    end
    -- hotkey: the first letter of the name no earlier item uses
    local hot = t.name
    for pos = 1, #t.name do
      local ch = t.name:sub(pos, pos):lower()
      if ch:match("%a") and not used[ch] then
        used[ch] = true
        hot = t.name:sub(1, pos - 1) .. "~" .. t.name:sub(pos, pos) .. "~" .. t.name:sub(pos + 1)
        break
      end
    end
    table.insert(items, {
      label = hot,
      hint = ("%s the block (or whole file)"):format(t.name),
      action = function(ctx) require("util.transform").run(t.name, ctx.visual) end,
    })
  end
  return items
end

-- File > Recent: the last files (TP listed them in File), then sessions
local function recent()
  local items = {}
  for _, f in ipairs(vim.v.oldfiles) do
    if #items == 9 then
      break
    end
    if vim.fn.filereadable(f) == 1 and not f:match("^/tmp/") then
      local dir = vim.fn.fnamemodify(f, ":~:.:h")
      table.insert(items, {
        label = ("~%d~ %s"):format(#items + 1, vim.fn.fnamemodify(f, ":t")),
        key = #dir > 24 and vim.fn.pathshorten(dir, 3) or dir,
        hint = "Reopen " .. vim.fn.fnamemodify(f, ":~"),
        action = function() vim.cmd.edit(vim.fn.fnameescape(f)) end,
      })
    end
  end
  if #items > 0 then
    table.insert(items, "-")
  end
  table.insert(items, { label = "~S~essions...", key = "Space q S", hint = "Restore a saved session",
    action = function() require("persistence").select() end })
  return items
end

-- menus are grouped by task; the look (frames, hotkeys, hints, F-keys) is Turbo Vision's
M.menus = {
  {
    title = "≡",
    items = {
      { label = "~S~ettings", hint = "Editor options, config files, colour scheme", items = {
        { label = "~E~ditor options...", hint = "Browse and change editor options", action = telescope("vim_options") },
        { label = "~C~onfig files...", key = "Space f c", hint = "Browse the Turbo Vim config directory",
          action = pick("files", { cwd = vim.fn.stdpath("config") }) },
        { label = "Colour ~s~cheme...", hint = "Try another colour scheme (default retrobox; the blue TP screen is `turbopascal`)",
          action = telescope("colorscheme", { enable_preview = true }) },
      } },
      { label = "~P~lugins", key = "Space l", hint = "Install, update and inspect plugins (:Lazy)", action = cmd("Lazy") },
      { label = "~L~anguage tools", key = "Space c m", hint = "Language servers, debuggers and formatters (:Mason)", action = cmd("Mason") },
      "-",
      { label = "~R~epaint desktop", hint = "Redraw the screen", action = cmd("mode") },
    },
  },
  {
    title = "~F~ile",
    items = {
      { label = "~N~ew", hint = "Create a new empty buffer", action = cmd("enew") },
      { label = "~O~pen...", key = "F3", hint = "Find and open a file", action = pick("files") },
      { label = "~R~ecent", hint = "Recently opened files and saved sessions", items = recent },
      { label = "File ~t~ree", key = "Space e", hint = "Show or hide the file explorer",
        action = function() Snacks.explorer({ cwd = LazyVim.root() }) end },
      "-",
      { label = "~S~ave", key = "F2", hint = "Save the file in the active window", action = cmd("write") },
      { label = "Save ~a~s...", hint = "Save the file under a new name",
        action = input("Save as: ", function() return vim.fn.expand("%") end, "file", function(v) vim.cmd.saveas(v) end) },
      { label = "Save a~l~l", hint = "Save all modified files", action = cmd("wall") },
      "-",
      { label = "~C~lose", key = "Shift+F3", hint = "Close the active file", action = function() Snacks.bufdelete() end },
      { label = "Clos~e~ all", hint = "Close all files", action = function() Snacks.bufdelete.all() end },
      "-",
      { label = "E~x~it", key = "Alt+X", hint = "Quit Turbo Vim", action = cmd("confirm qall") },
    },
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
      { label = "Clip~b~oard history...", hint = "Browse the registers", action = telescope("registers") },
      "-",
      { label = "Co~m~ment", key = "g c c", hint = "Comment or uncomment the block (or line)",
        action = function(ctx) vim.cmd("normal " .. (ctx.visual and "gvgc" or "gcc")) end },
      { label = "Tr~a~nsform", key = "Space c t", hint = "JSON, URL, HTML and Base64 on the block (or whole file)", items = transforms },
    },
  },
  {
    title = "~S~earch",
    items = {
      { label = "~F~ind...", key = "/", hint = "Search forward in this file", action = feed("/") },
      { label = "Find ~a~gain", key = "n", hint = "Repeat the last search",
        action = function()
          if vim.fn.getreg("/") == "" then
            return vim.notify("No previous search")
          end
          pcall(vim.cmd, "normal! n")
        end },
      { label = "~R~eplace...", key = "Space s r", hint = "Search and replace (grug-far)",
        action = function(ctx)
          local grug = require("grug-far")
          if ctx.visual then
            grug.with_visual_selection()
          else
            grug.open({ prefills = { search = vim.fn.expand("<cword>") } })
          end
        end },
      "-",
      { label = "Find in f~i~les...", key = "Shift+F2", hint = "Search the project with ripgrep", action = pick("live_grep") },
      { label = "Find ~l~ines...", key = "Space s B", hint = "Search the lines of this file",
        action = telescope("current_buffer_fuzzy_find", { fuzzy = false, case_mode = "ignore_case" }) },
      "-",
      { label = "~G~o to line...", hint = "Jump to a line in this file",
        action = input("Line number: ", nil, nil, function(v) vim.cmd(tostring(tonumber(v) or 1)) end) },
      { label = "Go to ~s~ymbol...", key = "Space s s", hint = "Jump to a function, type... in this file",
        action = telescope("lsp_document_symbols") },
      { label = "Go to symbol in ~w~orkspace...", key = "Space s S", hint = "Search symbols across the project",
        action = telescope("lsp_dynamic_workspace_symbols") },
    },
  },
  {
    title = "~C~ode",
    items = {
      { label = "Go to ~d~efinition", key = "g d", hint = "Jump to where the symbol under the cursor is defined",
        action = telescope("lsp_definitions") },
      { label = "~R~eferences", key = "g r", hint = "Every use of the symbol under the cursor", action = telescope("lsp_references") },
      "-",
      { label = "Re~n~ame...", key = "Space c r", hint = "Rename the symbol under the cursor everywhere", action = function() vim.lsp.buf.rename() end },
      { label = "Code ~a~ction...", key = "Space c a", hint = "Quick fixes and refactorings at the cursor",
        action = function() vim.lsp.buf.code_action() end },
      { label = "~F~ix all", key = "Space c F", hint = "Apply the quick fix of every diagnostic in this file",
        action = function() require("util.lsp").fix_all() end },
      { label = "F~o~rmat file", key = "Space c f", hint = "Format with the file type's formatter (conform)",
        action = function() LazyVim.format({ force = true }) end },
      "-",
      { label = "~P~roblems", hint = "Diagnostics of the language servers", items = {
        { label = "~A~ll files...", key = "Space s d", hint = "Diagnostics in every open file", action = telescope("diagnostics") },
        { label = "~T~his file...", key = "Space s D", hint = "Diagnostics in this file", action = telescope("diagnostics", { bufnr = 0 }) },
      } },
      { label = "~L~anguage servers...", key = "Space c l", hint = "Language servers attached to this file",
        action = function() Snacks.picker.lsp_config() end },
      { label = "R~e~start language servers", key = "Space c L", hint = "Restart the language servers of this file", action = cmd("lsp restart") },
    },
  },
  {
    title = "~B~uild",
    items = {
      { label = "~M~ake", key = "F9", hint = "Save all and run :make (Rust: cargo build)", action = M.make },
      "-",
      { label = "~C~ompiler messages", hint = "The quickfix list from the last Make", action = cmd("copen") },
      { label = "~N~ext message", key = "] q", hint = "Go to the next compiler message", action = M.messages("next") },
      { label = "~P~revious message", key = "[ q", hint = "Go to the previous compiler message", action = M.messages("prev") },
    },
  },
  {
    title = "~D~ebug",
    items = {
      { label = "~S~tart / continue", key = "Shift+F9", hint = "Start debugging, or continue to the next breakpoint", action = dap("continue") },
      { label = "S~t~op", key = "Shift+F5", hint = "Stop the debug session", action = dap("terminate") },
      { label = "~R~estart", key = "Space d r", hint = "Restart the debug session", action = dap("restart") },
      "-",
      { label = "Step ~o~ver", key = "F8", hint = "Execute the next line, stepping over calls", action = dap("step_over") },
      { label = "Step ~i~nto", key = "F7", hint = "Execute the next line, stepping into calls", action = dap("step_into") },
      { label = "Step o~u~t", key = "Shift+F8", hint = "Run until the current function returns", action = dap("step_out") },
      { label = "Run to ~c~ursor", key = "F4", hint = "Run until the cursor line", action = dap("run_to_cursor") },
      "-",
      { label = "~B~reakpoints", hint = "Set, clear and list breakpoints", items = {
        { label = "~T~oggle", key = "F5", hint = "Set or clear a breakpoint on this line", action = dap("toggle_breakpoint") },
        { label = "~C~onditional...", key = "Space d B", hint = "Add a conditional breakpoint on this line",
          action = input("Condition: ", nil, nil, function(v) require("dap").set_breakpoint(v) end) },
        { label = "~L~ogpoint...", key = "Space d l", hint = "Log a message when this line runs, without stopping",
          action = input("Log message: ", nil, nil, function(v) require("dap").set_breakpoint(nil, nil, v) end) },
        "-",
        { label = "Li~s~t all", hint = "All breakpoints, in the quickfix list",
          action = function() require("dap").list_breakpoints() vim.cmd("copen") end },
        { label = "Cl~e~ar all", key = "Space d C", hint = "Remove every breakpoint", action = dap("clear_breakpoints") },
      } },
      { label = "~A~dd watch...", key = "Shift+F7", hint = "Watch an expression",
        action = input("Add watch: ", function() return vim.fn.expand("<cword>") end, nil, function(v) dapui().elements.watches.add(v) end) },
      { label = "~E~valuate...", key = "Shift+F4", hint = "Evaluate the expression under the cursor",
        action = function() dapui().eval(nil, { enter = true }) end },
      "-",
      { label = "~V~iews", hint = "Watches, call stack, output, REPL and the debugger panels", items = {
        { label = "~W~atches", hint = "Show the watches", action = dapui_float("watches") },
        { label = "~C~all stack", key = "Space d s", hint = "Show the call stack", action = dapui_float("stacks") },
        { label = "~O~utput", hint = "Show the program output", action = dapui_float("console") },
        { label = "~R~EPL", key = "Space d R", hint = "Open the debugger's command line", action = function() require("dap").repl.open() end },
        "-",
        { label = "Debugger ~p~anels", key = "Space d u", hint = "Show or hide the debugger panels", action = function() dapui().toggle() end },
      } },
    },
  },
  { title = "~A~I", items = M.ai },
  {
    title = "~T~ools",
    items = {
      { label = "~G~it", hint = "Lazygit, log, diff and blame", items = M.git },
      { label = "~D~ocker", hint = "Docker explorer, logs and Lazydocker", items = M.docker },
      { label = "Data~b~ase", hint = "Dadbod database UI and queries", items = M.db },
    },
  },
  {
    title = "~W~indow",
    items = {
      { label = "Split ~b~elow", key = "Space -", hint = "Split the active window horizontally", action = cmd("wincmd s") },
      { label = "Split ~r~ight", key = "Space |", hint = "Split the active window vertically", action = cmd("wincmd v") },
      { label = "~C~lose window", key = "Space w d", hint = "Close the active window (the file stays open)",
        action = function() pcall(vim.cmd, "wincmd c") end },
      "-",
      { label = "~T~ile", key = "Ctrl+W =", hint = "Make all windows the same size", action = cmd("wincmd =") },
      { label = "~Z~oom", key = "Space w m", hint = "Maximise the active window, or restore it", action = function() Snacks.zen.zoom() end },
      "-",
      { label = "~N~ext", key = "F6", hint = "Go to the next window", action = cmd("wincmd w") },
      { label = "~P~revious", key = "Shift+F6", hint = "Go to the previous window", action = cmd("wincmd W") },
      { label = "~L~ist...", key = "Alt+0", hint = "Pick an open file", action = telescope("buffers", { sort_mru = true }) },
    },
  },
  {
    title = "~H~elp",
    items = {
      { label = "~C~ontents", key = "F1", hint = "Open the Neovim manual", action = cmd("help") },
      { label = "~I~ndex...", key = "Space s h", hint = "Search all help topics", action = telescope("help_tags") },
      { label = "~T~opic search", key = "Shift+F1", hint = "Help for the word under the cursor", action = M.topic_search },
      { label = "~K~eyboard shortcuts...", key = "Space s k", hint = "Search every key mapping", action = telescope("keymaps") },
      "-",
      { label = "~A~bout...", hint = "Show version and copyright information", action = chrome.about },
    },
  },
}

-- the edit window's local menu (Shift+F10 / right click): clipboard,
-- navigation, then the debugger at the cursor
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
  { label = "Go to ~d~efinition", key = "g d", hint = "Go to the definition of the symbol under the cursor",
    action = function() vim.lsp.buf.definition() end },
  { label = "Topic ~s~earch", key = "Shift+F1", hint = "Help for the word under the cursor", action = M.topic_search },
  "-",
  { label = "Toggle ~b~reakpoint", key = "F5", hint = "Set or clear a breakpoint on this line", action = dap("toggle_breakpoint") },
  { label = "~R~un to cursor", key = "F4", hint = "Run until the cursor line", action = dap("run_to_cursor") },
  { label = "~E~valuate...", key = "Shift+F4", hint = "Evaluate the expression under the cursor",
    action = function() dapui().eval(nil, { enter = true }) end },
  { label = "~A~dd watch...", key = "Shift+F7", hint = "Watch an expression",
    action = input("Add watch: ", function() return vim.fn.expand("<cword>") end, nil, function(v) dapui().elements.watches.add(v) end) },
  "-",
  { label = "~I~nline AI edit...", key = "Space a i", hint = "Ask the AI to edit the block (or line) in place",
    action = function(ctx) vim.cmd(range(ctx) .. "CodeCompanion") end },
}

return M
