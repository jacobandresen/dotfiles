-- Client tuning is per host; server RAM/OS profiles remain in ollama/.
-- Unknown hosts retain the original settings rather than inheriting a
-- discrete-GPU host's memory budget. Model selection stays dynamic.
local M = {}
local defaults = {
  chat = {}, -- inherit this host's Ollama server defaults
  inline = { num_ctx = 2048, num_predict = 512, keep_alive = "30m" },
  completion = {
    context_window = 512, -- characters, not tokens
    request_timeout = 10,
    throttle = 2000,
    debounce = 800,
    max_tokens = 128,
  },
}

local hosts = {
  -- i3-9100F, 16 GiB RAM, GTX 1660 SUPER (6 GiB VRAM).
  -- qwen3.5:4b is fully GPU-resident at 8192 context (~3.18 GiB model).
  -- Match the server/Minuet context so inline edits do not request a
  -- different runner allocation. Keep one shared model, as the daemon does.
  -- Timing probes on 2026-10-03 hit the shared queue; these are conservative
  -- settings, not a claimed throughput optimum.
  tatooine = {
    chat = { num_ctx = 8192, think = false, keep_alive = "10m" },
    inline = { num_ctx = 8192, keep_alive = "10m" },
    completion = {
      context_window = 2048, -- ~512 tokens of code plus Minuet's prompt
      max_tokens = 96,
      temperature = 0.2,
      throttle = 3000,
    },
  },
}

function M.for_host(host)
  return vim.tbl_deep_extend("force", vim.deepcopy(defaults), hosts[host] or {})
end

function M.current()
  return M.for_host(vim.uv.os_gethostname())
end

return M
