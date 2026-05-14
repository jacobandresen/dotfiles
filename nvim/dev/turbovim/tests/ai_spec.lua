local menus   = require("turbovim.menus").get()
local ai_menu = menus[7]   -- AI is at index 7 (File/Edit/Search/Code/Database/Run/AI/Window/Help)

-- ── Structure ────────────────────────────────────────────────────────────────

describe("AI menu: structure", function()

  it("is at index 7 with label 'AI' and key 'a'", function()
    assert.equals("AI",  ai_menu.label)
    assert.equals("a",   ai_menu.key)
  end)

  it("has exactly 3 items and no separators", function()
    local count = 0
    for _, item in ipairs(ai_menu.items) do
      if not item.sep then count = count + 1 end
    end
    assert.equals(3, count)
  end)

  it("Chat is item 1: key 'c', hint '<leader>cc'", function()
    local item = ai_menu.items[1]
    assert.equals("Chat",        item.label)
    assert.equals("c",           item.key)
    assert.equals("<leader>cc",  item.hint)
    assert.is_function(item.action)
  end)

  it("Actions is item 2: key 'a', hint '<leader>ca'", function()
    local item = ai_menu.items[2]
    assert.equals("Actions",     item.label)
    assert.equals("a",           item.key)
    assert.equals("<leader>ca",  item.hint)
    assert.is_function(item.action)
  end)

  it("Inline is item 3: key 'i', hint '<leader>ci'", function()
    local item = ai_menu.items[3]
    assert.equals("Inline",      item.label)
    assert.equals("i",           item.key)
    assert.equals("<leader>ci",  item.hint)
    assert.is_function(item.action)
  end)

end)

-- ── Action dispatch ───────────────────────────────────────────────────────────

describe("AI menu: action dispatch", function()
  local orig_cmd, captured

  before_each(function()
    orig_cmd = vim.cmd
    captured = nil
    vim.cmd  = function(c) captured = c end
  end)

  after_each(function()
    vim.cmd = orig_cmd
  end)

  it("Chat dispatches 'CodeCompanionChat Toggle'", function()
    ai_menu.items[1].action()
    assert.equals("CodeCompanionChat Toggle", captured)
  end)

  it("Actions dispatches 'CodeCompanionActions'", function()
    ai_menu.items[2].action()
    assert.equals("CodeCompanionActions", captured)
  end)

  it("Inline dispatches 'CodeCompanion'", function()
    ai_menu.items[3].action()
    assert.equals("CodeCompanion", captured)
  end)

end)

-- ── No warnings on dispatch (all menus) ──────────────────────────────────────
--
-- Each action is called with all external dependencies stubbed so the test
-- environment matches "plugin not yet loaded" — the same state a user is in
-- the first time they open a menu entry.  Any vim.notify at WARN level or
-- above is recorded as a failure.

describe("all menu entries: no warnings on dispatch", function()

  local orig_cmd, orig_notify, orig_feedkeys
  local orig_lsp_buf_code_action, orig_lsp_buf_rename
  local orig_lsp_buf_format, orig_lsp_buf_hover, orig_lsp_buf_definition
  local warnings

  before_each(function()
    warnings = {}

    orig_notify  = vim.notify
    vim.notify   = function(msg, level)
      if level and level >= vim.log.levels.WARN then
        table.insert(warnings, tostring(msg))
      end
    end

    orig_cmd = vim.cmd
    vim.cmd  = function() end

    orig_feedkeys        = vim.api.nvim_feedkeys
    vim.api.nvim_feedkeys = function() end

    -- Stub individual lsp methods rather than the whole table to avoid
    -- breaking any other Neovim internals that might reference vim.lsp.buf
    local buf = vim.lsp.buf
    orig_lsp_buf_code_action = buf.code_action
    orig_lsp_buf_rename      = buf.rename
    orig_lsp_buf_format      = buf.format
    orig_lsp_buf_hover       = buf.hover
    orig_lsp_buf_definition  = buf.definition
    buf.code_action = function() end
    buf.rename      = function() end
    buf.format      = function() end
    buf.hover       = function() end
    buf.definition  = function() end

    -- Inject noop shims for lazily-required modules
    local noop = setmetatable({}, { __index = function() return function() end end })
    package.loaded["telescope.builtin"] = noop
    package.loaded["turbovim.splash"]   = { show = function() end }
  end)

  after_each(function()
    vim.notify           = orig_notify
    vim.cmd              = orig_cmd
    vim.api.nvim_feedkeys = orig_feedkeys

    local buf = vim.lsp.buf
    buf.code_action = orig_lsp_buf_code_action
    buf.rename      = orig_lsp_buf_rename
    buf.format      = orig_lsp_buf_format
    buf.hover       = orig_lsp_buf_hover
    buf.definition  = orig_lsp_buf_definition

    package.loaded["telescope.builtin"] = nil
    package.loaded["turbovim.splash"]   = nil
  end)

  for _, menu in ipairs(menus) do
    for _, item in ipairs(menu.items) do
      if not item.sep then
        it(menu.label .. " > " .. item.label .. ": no warnings", function()
          warnings = {}
          item.action()
          assert.equals(0, #warnings,
            "unexpected warning(s): " .. table.concat(warnings, "; "))
        end)
      end
    end
  end

end)
