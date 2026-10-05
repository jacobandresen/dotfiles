-- Text transformations (JSON, URL, HTML, Base64) piped through external
-- tools, applied to the visual selection or the whole buffer.
local M = {}

-- Homebrew prefixes GNU coreutils; its base64 supports the flags below.
local base64 = vim.fn.executable("gbase64") == 1 and "gbase64" or "base64"
local py = [[python3 -c "import sys,%s;print(%s(sys.stdin.read()%s),end='')"]]

M.transformations = {
  { name = "JSON Prettify", cmd = "jq ." },
  { name = "JSON Minify", cmd = "jq -c ." },
  { name = "JSON Escape", cmd = "jq -Rs ." },
  { name = "JSON Unescape", cmd = "jq -r ." },
  { name = "URL Encode", cmd = py:format("urllib.parse", "urllib.parse.quote", "") },
  { name = "URL Decode", cmd = py:format("urllib.parse", "urllib.parse.unquote", "") },
  { name = "HTML Escape", cmd = py:format("html", "html.escape", "") },
  { name = "HTML Unescape", cmd = py:format("html", "html.unescape", "") },
  { name = "Base64 Encode", cmd = base64 .. " -w0" },
  { name = "Base64 Decode", cmd = base64 .. " -d" },
}

-- returns the text plus its {row, col} start/end, or nil range for the buffer
local function get_text(mode)
  if mode == "v" or mode == "V" then
    local s, e = vim.fn.getpos("'<"), vim.fn.getpos("'>")
    local start_row, start_col = s[2] - 1, s[3] - 1
    local end_row, end_col = e[2] - 1, e[3]
    local end_line = vim.api.nvim_buf_get_lines(0, end_row, end_row + 1, false)[1] or ""
    if mode == "V" then
      start_col, end_col = 0, #end_line
    else
      -- Visual marks point at the first byte of the final character.
      local character = vim.fn.strcharpart(end_line:sub(end_col), 0, 1)
      end_col = math.min(end_col - 1 + #character, #end_line)
    end
    local lines = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
    return table.concat(lines, "\n"), { start_row, start_col, end_row, end_col }
  end
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"), nil
end

local function capture(mode)
  if mode == "\22" then
    vim.notify("Transforms need a character or line selection; block selections are not supported", vim.log.levels.WARN)
    return
  end
  if not vim.bo.modifiable then
    vim.notify("This buffer is read-only; switch to Edit mode before transforming", vim.log.levels.WARN)
    return
  end
  local text, range = get_text(mode)
  if text == "" then
    vim.notify("No text to transform", vim.log.levels.WARN)
    return
  end
  return { buf = vim.api.nvim_get_current_buf(), tick = vim.b.changedtick, text = text, range = range }
end

local function apply(cmd, snapshot)
  local buf, range = snapshot.buf, snapshot.range
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return vim.notify("The transform buffer was closed", vim.log.levels.WARN)
  end
  if vim.api.nvim_buf_get_changedtick(buf) ~= snapshot.tick then
    return vim.notify("The buffer changed while choosing a transform; select it again", vim.log.levels.WARN)
  end
  if not vim.bo[buf].modifiable then
    return vim.notify("The transform buffer is now read-only", vim.log.levels.WARN)
  end
  local result = vim.fn.system(cmd, snapshot.text)
  if vim.v.shell_error ~= 0 then
    vim.notify("Transform failed: " .. result, vim.log.levels.ERROR)
    return
  end
  local lines = vim.split(result, "\n")
  if #lines > 1 and lines[#lines] == "" then
    table.remove(lines)
  end
  if range then
    vim.api.nvim_buf_set_text(buf, range[1], range[2], range[3], range[4], lines)
  else
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
end

function M.pick()
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    -- leave visual mode so the '< and '> marks are set
    vim.cmd("normal! \27")
  end
  local snapshot = capture(mode)
  if not snapshot then return end
  vim.ui.select(M.transformations, {
    prompt = "Transform",
    format_item = function(t) return t.name end,
  }, function(choice)
    if choice then
      apply(choice.cmd, snapshot)
    end
  end)
end

-- one transformation by name, on the selection when `visual`, else the
-- whole buffer (for the Edit > Transform menu, which has left Visual mode)
function M.run(name, visual)
  for _, t in ipairs(M.transformations) do
    if t.name == name then
      local snapshot = capture(visual and vim.fn.visualmode() or "n")
      if snapshot then return apply(t.cmd, snapshot) end
    end
  end
end

return M
