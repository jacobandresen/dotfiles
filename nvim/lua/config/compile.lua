-- config/compile.lua
local M = {}

-- filetype -> compile command ("%" = full path, "%:r" = filename without extension)
M.commands = {
  c        = { cmd = "gcc -Wall -o %:r % && ./%:r",        desc = "C (gcc)" },
  cpp      = { cmd = "g++ -Wall -std=c++20 -o %:r % && ./%:r", desc = "C++ (g++)" },
  rust     = { cmd = "cargo run",                         desc = "Rust (cargo)" },
  go       = { cmd = "go run %",                          desc = "Go" },
  python   = { cmd = "python3 %",                         desc = "Python" },
  lua      = { cmd = "lua %",                             desc = "Lua" },
  java     = { cmd = "javac % && java %:r",                desc = "Java" },
  javascript = { cmd = "node %",                          desc = "Node.js" },
  typescript = { cmd = "ts-node %",                      desc = "TS‑Node" },
  sh       = { cmd = "bash %",                            desc = "Shell" },
  ruby     = { cmd = "ruby %",                            desc = "Ruby" },
  perl     = { cmd = "perl %",                            desc = "Perl" },
}

function M.get_cmd()
  local ft = vim.bo.filetype
  local entry = M.commands[ft]
  if not entry then return nil end
  local cmd = entry.cmd
  cmd = cmd:gsub("%%:r", vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":r"))
  cmd = cmd:gsub("%%", vim.api.nvim_buf_get_name(0))
  return cmd, entry.desc
end

return M
