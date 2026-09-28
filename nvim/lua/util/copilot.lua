local M = {}

local function config_path()
  local path = vim.env.CODECOMPANION_TOKEN_PATH
  if path and path ~= "" then
    return vim.fs.normalize(path)
  end

  path = vim.env.XDG_CONFIG_HOME
  if path and path ~= "" and vim.fn.isdirectory(path) == 1 then
    return vim.fs.normalize(path)
  end

  return vim.fs.normalize("~/.config")
end

local function has_oauth_token(path)
  if not vim.uv.fs_stat(path) then
    return false
  end

  local ok, contents = pcall(vim.fn.readfile, path)
  if not ok then
    return false
  end

  local decoded_ok, hosts = pcall(vim.json.decode, table.concat(contents, "\n"))
  if not decoded_ok or type(hosts) ~= "table" then
    return false
  end

  for host, credentials in pairs(hosts) do
    if host:find("github.com", 1, true) and type(credentials) == "table"
      and type(credentials.oauth_token) == "string" and credentials.oauth_token ~= "" then
      return true
    end
  end

  return false
end

function M.is_configured()
  if vim.env.CODESPACES and vim.env.GITHUB_TOKEN and vim.env.GITHUB_TOKEN ~= "" then
    return true
  end

  local copilot_path = vim.fs.joinpath(config_path(), "github-copilot")
  if has_oauth_token(vim.fs.joinpath(copilot_path, "hosts.json"))
    or has_oauth_token(vim.fs.joinpath(copilot_path, "apps.json")) then
    return true
  end

  local auth_db = vim.fs.joinpath(copilot_path, "auth.db")
  return vim.fn.executable("sqlite3") == 1 and vim.uv.fs_stat(auth_db) ~= nil
end

return M
