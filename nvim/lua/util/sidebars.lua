local M = {}
local kinds = { snacks_picker_list = "files", dbui = "database", ["neotest-summary"] = "tests" }

function M.keep(kind)
  local current = vim.api.nvim_get_current_win()
  local explorers = kind ~= "files" and Snacks.picker.get({ source = "explorer" }) or {}
  local closing = {}
  for _, picker in ipairs(explorers) do
    for _, part in ipairs({ picker.list, picker.input, picker.preview }) do
      if part.win.win then closing[part.win.win] = true end
    end
    picker:close()
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
      if (ft == "dbui" or ft == "neotest-summary") and kinds[ft] ~= kind then vim.api.nvim_win_close(win, false) end
    end
  end
  if closing[current] then
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if
        not closing[win]
        and vim.api.nvim_win_get_config(win).relative == ""
        and vim.bo[vim.api.nvim_win_get_buf(win)].buftype ~= "nofile"
      then
        vim.api.nvim_set_current_win(win)
        break
      end
    end
  elseif vim.api.nvim_win_is_valid(current) then
    vim.api.nvim_set_current_win(current)
  end
  return #explorers > 0
end

function M.setup()
  local pending = {}
  vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
    group = vim.api.nvim_create_augroup("one_sidebar", { clear = true }),
    callback = function(ev)
      if not kinds[vim.bo[ev.buf].filetype] then return end
      local tab = vim.api.nvim_get_current_tabpage()
      if pending[tab] then
        pending[tab][#pending[tab] + 1] = ev.buf
        return
      end
      local buffers = { ev.buf }
      pending[tab] = buffers
      vim.schedule(function()
        pending[tab] = nil
        if not vim.api.nvim_tabpage_is_valid(tab) then return end
        -- The last opened sidebar wins, including several opens within one event-loop tick.
        for index = #buffers, 1, -1 do
          local buf = buffers[index]
          if vim.api.nvim_buf_is_valid(buf) then
            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
              if vim.api.nvim_win_get_buf(win) == buf then
                local claimed = false
                vim.api.nvim_win_call(win, function()
                  local kind = kinds[vim.bo[buf].filetype]
                  if kind == "files" then
                    local explorer = false
                    for _, picker in ipairs(Snacks.picker.get({ source = "explorer" })) do
                      if picker.list.win.buf == buf then explorer = true end
                    end
                    if not explorer then return end
                  end
                  if kind then
                    M.keep(kind)
                    claimed = true
                  end
                end)
                if claimed then return end
              end
            end
          end
        end
      end)
    end,
  })
end

return M
