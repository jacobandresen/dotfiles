local menus = require("turbovim.menus").get()

local expected_menus = {
  { label = "File",     key = "f" },
  { label = "Edit",     key = "e" },
  { label = "Search",   key = "s" },
  { label = "Code",     key = "c" },
  { label = "Database", key = "d" },
  { label = "Run",      key = "r" },
  { label = "AI",       key = "a" },
  { label = "Window",   key = "w" },
  { label = "Help",     key = "h" },
}

describe("turbovim menu structure", function()

  it("has 9 top-level menus", function()
    assert.equals(9, #menus)
  end)

  it("top-level menu labels are in expected order", function()
    for i, exp in ipairs(expected_menus) do
      assert.equals(exp.label, menus[i].label)
    end
  end)

  it("top-level menu keys are in expected order", function()
    for i, exp in ipairs(expected_menus) do
      assert.equals(exp.key, menus[i].key)
    end
  end)

  it("top-level menu keys are unique", function()
    local seen = {}
    for _, menu in ipairs(menus) do
      assert.is_nil(seen[menu.key], "duplicate top-level key: " .. menu.key)
      seen[menu.key] = true
    end
  end)

  for _, menu in ipairs(menus) do
    describe("menu: " .. menu.label, function()

      it("has an items table with at least one entry", function()
        assert.is_table(menu.items)
        assert.is_true(#menu.items > 0)
      end)

      it("item keys are unique within the menu", function()
        local seen = {}
        for _, item in ipairs(menu.items) do
          if not item.sep then
            local msg = "duplicate key '" .. item.key .. "' in " .. menu.label
            assert.is_nil(seen[item.key], msg)
            seen[item.key] = true
          end
        end
      end)

      it("separators have sep=true and no label or action", function()
        for _, item in ipairs(menu.items) do
          if item.sep then
            assert.is_true(item.sep)
            assert.is_nil(item.label)
            assert.is_nil(item.action)
          end
        end
      end)

      for _, item in ipairs(menu.items) do
        if not item.sep then
          it("item '" .. item.label .. "' has label, key, and action", function()
            assert.is_string(item.label)
            assert.is_string(item.key)
            assert.is_function(item.action)
          end)
        end
      end

    end)
  end

end)
