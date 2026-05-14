local state    = require("turbovim.state")
local dropdown = require("turbovim.dropdown")

local function reset_state()
  state.active         = false
  state.item_idx       = 1
  state.dropdown_open  = false
  state.dropdown_idx   = 1
  state.dropdown_buf   = nil
  state.dropdown_win   = nil
  state.dropdown_items = nil
  state.dropdown_lines = nil
  state.dropdown_menu  = nil
end

local function item(label, key)
  return { label = label, key = key, hint = "", action = function() end }
end

describe("dropdown.move()", function()
  before_each(reset_state)

  it("advances idx by one", function()
    state.dropdown_items = { item("A", "a"), item("B", "b"), item("C", "c") }
    state.dropdown_idx = 1
    dropdown.move(1)
    assert.equals(2, state.dropdown_idx)
  end)

  it("retreats idx by one", function()
    state.dropdown_items = { item("A", "a"), item("B", "b"), item("C", "c") }
    state.dropdown_idx = 3
    dropdown.move(-1)
    assert.equals(2, state.dropdown_idx)
  end)

  it("skips separator (false) when moving down", function()
    state.dropdown_items = { item("A", "a"), item("B", "b"), false, item("C", "c") }
    state.dropdown_idx = 2
    dropdown.move(1)
    assert.equals(4, state.dropdown_idx)
  end)

  it("skips separator (false) when moving up", function()
    state.dropdown_items = { item("A", "a"), false, item("B", "b"), item("C", "c") }
    state.dropdown_idx = 3
    dropdown.move(-1)
    assert.equals(1, state.dropdown_idx)
  end)

  it("does not advance past the last real item", function()
    state.dropdown_items = { item("A", "a"), item("B", "b") }
    state.dropdown_idx = 2
    dropdown.move(1)
    assert.equals(2, state.dropdown_idx)
  end)

  it("does not retreat past the first real item", function()
    state.dropdown_items = { item("A", "a"), item("B", "b") }
    state.dropdown_idx = 1
    dropdown.move(-1)
    assert.equals(1, state.dropdown_idx)
  end)

  it("does not advance when trailing entries are all separators", function()
    state.dropdown_items = { item("A", "a"), item("B", "b"), false }
    state.dropdown_idx = 2
    dropdown.move(1)
    assert.equals(2, state.dropdown_idx)
  end)
end)

describe("dropdown.execute()", function()
  before_each(reset_state)

  it("calls the action of the selected item", function()
    local called = false
    state.dropdown_items = { { label = "T", key = "t", hint = "", action = function() called = true end } }
    state.dropdown_idx = 1
    dropdown.execute()
    vim.wait(200, function() return called end, 10)
    assert.is_true(called)
  end)

  it("clears dropdown state (buf, win, items) after execute", function()
    state.dropdown_items = { item("T", "t") }
    state.dropdown_idx = 1
    dropdown.execute()
    assert.is_nil(state.dropdown_buf)
    assert.is_nil(state.dropdown_win)
    assert.is_nil(state.dropdown_items)
    assert.is_nil(state.dropdown_lines)
    assert.is_nil(state.dropdown_menu)
  end)

  it("sets state.active to false after execute", function()
    state.active = true
    state.dropdown_items = { item("T", "t") }
    state.dropdown_idx = 1
    dropdown.execute()
    assert.is_false(state.active)
  end)

  it("does nothing when dropdown_items is nil", function()
    state.dropdown_items = nil
    assert.has_no.errors(function() dropdown.execute() end)
  end)
end)
