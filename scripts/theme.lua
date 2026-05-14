#!/usr/bin/env lua
-- base16 theme manager: list | preview | set

-- ── YAML parsing ─────────────────────────────────────────────────────────────

local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

local function unquote(s)
  return (s:gsub('^["\']', ''):gsub('["\']$', ''))
end

local function parse_scheme(path)
  local file, err = io.open(path, "r")
  if not file then return nil, err end
  local scheme = { palette = {} }
  local in_palette = false
  for line in file:lines() do
    if line:match("^palette%s*:") then
      in_palette = true
    elseif line:match("^%S") then
      in_palette = false
    end
    if not in_palette then
      for _, field in ipairs({ "name", "author", "system", "slug", "variant" }) do
        local val = line:match("^" .. field .. "%s*:%s*(.-)%s*$")
        if val then scheme[field] = unquote(trim(val)) end
      end
    end
    -- base colors at any indent; handle "#{hex}" and #{hex} and bare hex
    local slot, hex = line:match('^%s*base(%x%x)%s*:%s*"?#?(%x%x%x%x%x%x)')
    if slot then scheme.palette[slot:lower()] = hex:lower() end
  end
  file:close()
  return scheme
end

-- ── ANSI helpers ─────────────────────────────────────────────────────────────

local function hex_to_rgb(hex)
  return tonumber(hex:sub(1, 2), 16),
         tonumber(hex:sub(3, 4), 16),
         tonumber(hex:sub(5, 6), 16)
end

local function bg_block(hex)
  local r, g, b = hex_to_rgb(hex)
  return ("\27[48;2;%d;%d;%dm   \27[0m"):format(r, g, b)
end

local function fg_on_bg(fghex, bghex)
  local fr, fg, fb = hex_to_rgb(fghex)
  local br, bg, bb = hex_to_rgb(bghex)
  return ("\27[38;2;%d;%d;%dm\27[48;2;%d;%d;%dm %s \27[0m"):format(
    fr, fg, fb, br, bg, bb, fghex)
end

-- ── list <dir> ───────────────────────────────────────────────────────────────

local function cmd_list(dir)
  local handle = io.popen(('find %q -name "*.yaml" -type f 2>/dev/null'):format(dir))
  if not handle then
    io.stderr:write("error: cannot list " .. dir .. "\n")
    os.exit(1)
  end
  local items = {}
  for yaml_path in handle:lines() do
    local scheme = parse_scheme(yaml_path)
    if scheme and scheme.name and #scheme.name > 0 then
      items[#items + 1] = { name = scheme.name, path = yaml_path }
    end
  end
  handle:close()
  table.sort(items, function(a, b) return a.name:lower() < b.name:lower() end)
  for _, item in ipairs(items) do
    io.write(item.name .. "\t" .. item.path .. "\n")
  end
end

-- ── preview <yaml_path> ───────────────────────────────────────────────────────

local function cmd_preview(yaml_path)
  local scheme, err = parse_scheme(yaml_path)
  if not scheme then
    io.stderr:write("error: " .. (err or "cannot read " .. yaml_path) .. "\n")
    os.exit(1)
  end

  local labels_lo = { "Background", "Alt Bg", "Selection", "Comments",
                      "Dark Fg", "Foreground", "Light Fg", "Light Bg" }
  local labels_hi = { "Red", "Orange", "Yellow", "Green",
                      "Cyan", "Blue", "Magenta", "Brown" }

  print()
  print(("  \27[1m%s\27[0m"):format(scheme.name or "unknown"))
  if scheme.author and #scheme.author > 0 then
    print(("  by %s"):format(scheme.author))
  end
  print()

  -- structural colors base00–07
  io.write("  ")
  for i = 0, 7 do
    local hex = scheme.palette[("%02x"):format(i)]
    io.write(hex and bg_block(hex) or "   ")
  end
  io.write("\n  ")
  for i = 0, 7 do io.write((" %s "):format(labels_lo[i + 1]:sub(1, 1))) end
  io.write("\n\n  ")

  -- accent colors base08–0f
  for i = 8, 15 do
    local hex = scheme.palette[("%02x"):format(i)]
    io.write(hex and bg_block(hex) or "   ")
  end
  io.write("\n  ")
  for i = 0, 7 do io.write((" %s "):format(labels_hi[i + 1]:sub(1, 1))) end
  io.write("\n\n")

  -- accents on background
  local bg = scheme.palette["00"]
  if bg then
    io.write("  Accents on background:\n  ")
    for i = 8, 15 do
      local hex = scheme.palette[("%02x"):format(i)]
      io.write(hex and fg_on_bg(hex, bg) or "       ")
    end
    io.write("\n\n")
  end

  -- full palette listing
  print("  Palette:")
  for i = 0, 15 do
    local slot = ("%02x"):format(i)
    local hex = scheme.palette[slot]
    if hex then
      print(("  %s base%s #%s"):format(bg_block(hex), slot, hex))
    end
  end
  print()
end

-- ── set <config_path> <scheme_name> ──────────────────────────────────────────

local function cmd_set(config_path, scheme_name)
  local file, err = io.open(config_path, "r")
  if not file then
    io.stderr:write("error: cannot read " .. config_path .. ": " .. (err or "") .. "\n")
    os.exit(1)
  end
  local content = file:read("*a")
  file:close()

  local new_line = ('config.color_scheme = "%s (base16)"'):format(scheme_name)
  local updated, n = content:gsub("config%.color_scheme%s*=[^\n]*", new_line)
  if n == 0 then
    io.stderr:write("warning: no config.color_scheme line found in " .. config_path .. "\n")
    os.exit(1)
  end

  local out, err2 = io.open(config_path, "w")
  if not out then
    io.stderr:write("error: cannot write " .. config_path .. ": " .. (err2 or "") .. "\n")
    os.exit(1)
  end
  out:write(updated)
  out:close()
end

-- ── dispatch ──────────────────────────────────────────────────────────────────

local subcmd = arg and arg[1]
if subcmd == "list" then
  cmd_list(arg[2] or (io.stderr:write("usage: theme.lua list <dir>\n") and os.exit(1)))
elseif subcmd == "preview" then
  cmd_preview(arg[2] or (io.stderr:write("usage: theme.lua preview <yaml_path>\n") and os.exit(1)))
elseif subcmd == "set" then
  if not arg[2] or not arg[3] then
    io.stderr:write("usage: theme.lua set <config_path> <scheme_name>\n")
    os.exit(1)
  end
  cmd_set(arg[2], arg[3])
else
  io.stderr:write("usage: theme.lua list|preview|set ...\n")
  os.exit(1)
end
