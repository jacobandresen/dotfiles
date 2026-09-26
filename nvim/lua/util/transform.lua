-- Text transformations (JSON, URL, HTML, Base64) piped through external
-- tools, applied to the visual selection or the whole buffer.
local M = {}

local py = [[python3 -c "import sys,%s;print(%s(sys.stdin.read()%s),end='')"]]

local transformations = {
  { name = "JSON Prettify", cmd = "jq ." },
  { name = "JSON Minify", cmd = "jq -c ." },
  { name = "JSON Escape", cmd = "jq -Rs ." },
  { name = "JSON Unescape", cmd = "jq -r ." },
  { name = "URL Encode", cmd = py:format("urllib.parse", "urllib.parse.quote", ".strip()") },
  { name = "URL Decode", cmd = py:format("urllib.parse", "urllib.parse.unquote", ".strip()") },
  { name = "HTML Escape", cmd = py:format("html", "html.escape", "") },
  { name = "HTML Unescape", cmd = py:format("html", "html.unescape", "") },
  { name = "Base64 Encode", cmd = "base64 -w0" },
  { name = "Base64 Decode", cmd = "base64 -d" },
}

-- returns the text plus its {row, col} start/end, or nil range for the buffer
local function get_text(mode)
  if mode == "v" or mode == "V" or mode == "\22" then
    local s, e = vim.fn.getpos("'<"), vim.fn.getpos("'>")
    local start_row, start_col = s[2] - 1, s[3] - 1
    local end_row, end_col = e[2] - 1, e[3]
    local end_line = vim.api.nvim_buf_get_lines(0, end_row, end_row + 1, false)[1] or ""
    if mode == "V" then
      start_col, end_col = 0, #end_line
    else
      end_col = math.min(end_col, #end_line)
    end
    local lines = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
    return table.concat(lines, "\n"), { start_row, start_col, end_row, end_col }
  end
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"), nil
end

local function apply(cmd, mode)
  local text, range = get_text(mode)
  if text == "" then
    vim.notify("No text to transform", vim.log.levels.WARN)
    return
  end
  local result = vim.fn.system(cmd, text)
  if vim.v.shell_error ~= 0 then
    vim.notify("Transform failed: " .. result, vim.log.levels.ERROR)
    return
  end
  local lines = vim.split(result, "\n")
  if #lines > 1 and lines[#lines] == "" then
    table.remove(lines)
  end
  if range then
    vim.api.nvim_buf_set_text(0, range[1], range[2], range[3], range[4], lines)
  else
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  end
end

function M.pick()
  local mode = vim.fn.mode()
  if mode ~= "n" then
    -- leave visual mode so the '< and '> marks are set
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  end
  vim.ui.select(transformations, {
    prompt = "Transform",
    format_item = function(t) return t.name end,
  }, function(choice)
    if choice then
      apply(choice.cmd, mode)
    end
  end)
end

return M
