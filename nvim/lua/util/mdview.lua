-- Markdown View/Edit modes. Edit shows the source; View renders it with
-- render-markdown.nvim (every line, the cursor line too), read-only and
-- soft-wrapped like a document. Toggle with <leader>um.
local M = {}

-- window options View changes, restored when going back to Edit
local view_wo = { wrap = true, linebreak = true, number = false, relativenumber = false, list = false, spell = false }

function M.is_markdown(buf)
  return vim.bo[buf or 0].filetype == "markdown"
end

function M.is_view(buf)
  return vim.b[buf or 0].md_view == true
end

-- the Edit-mode options last seen, for windows that copied View's options
-- from a split (window variables don't travel with a split, options do)
local edit_wo ---@type table?

local function apply_window(win, view)
  if view then
    if not vim.w[win].md_saved then
      local saved = {}
      for k in pairs(view_wo) do
        saved[k] = vim.wo[win][k]
      end
      vim.w[win].md_saved = saved
      edit_wo = saved
    end
    for k, v in pairs(view_wo) do
      vim.wo[win][k] = v
    end
  elseif vim.w[win].md_saved then
    for k, v in pairs(vim.w[win].md_saved) do
      vim.wo[win][k] = v
    end
    vim.w[win].md_saved = nil
  elseif edit_wo and vim.iter(view_wo):all(function(k, v) return vim.wo[win][k] == v end) then
    for k, v in pairs(edit_wo) do
      vim.wo[win][k] = v
    end
  end
end

---@param buf? integer
---@param view boolean
function M.set(buf, view)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if not M.is_markdown(buf) then
    return vim.notify("View mode is for markdown files", vim.log.levels.WARN)
  end
  if view and vim.bo[buf].modified then
    -- View is read-only; keep the unsaved edits visible but say so
    vim.notify("Unsaved changes are shown; save before switching to View mode")
  end
  vim.b[buf].md_view = view
  vim.bo[buf].modifiable = not view
  vim.api.nvim_buf_call(buf, function()
    require("render-markdown").set_buf(view)
  end)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    apply_window(win, view)
  end
  vim.cmd.redrawstatus({ bang = true })
end

function M.toggle(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  M.set(buf, not M.is_view(buf))
end

function M.setup()
  local group = vim.api.nvim_create_augroup("mdview", { clear = true })
  -- a View buffer shown in another window gets the View window options there too,
  -- and a window that switches to another buffer gets its own options back
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      apply_window(vim.api.nvim_get_current_win(), M.is_markdown(ev.buf) and M.is_view(ev.buf))
    end,
  })
end

return M
