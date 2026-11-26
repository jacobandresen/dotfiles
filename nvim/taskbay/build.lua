-- lazy.nvim runs this after installing or updating taskbay: it installs the pinned
-- dependencies of the pi driver's extension (the same as :TaskbaySetup).
local dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/agents/pi"
assert(vim.fn.executable("npm") == 1, "taskbay: npm is required by the pi agent driver")
local result = vim.system({ "npm", "ci", "--ignore-scripts", "--omit=dev" }, { cwd = dir, text = true }):wait()
assert(result.code == 0, "taskbay: npm ci failed in " .. dir .. "\n" .. (result.stderr or ""))
