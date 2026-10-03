-- NVIM_LOG_FILE=/tmp/nvim-tests.log nvim --headless -u NONE -i NONE -l nvim/tests/ollama_tuning.lua
local root = vim.fn.getcwd()
package.path = root .. "/nvim/lua/?.lua;" .. package.path
local tuning = require("util.ollama_tuning")
local local_profile = tuning.for_host("tatooine")
assert(local_profile.chat.num_ctx == local_profile.inline.num_ctx)
assert(local_profile.inline.num_ctx == 8192 and local_profile.inline.keep_alive == "10m")
local other = tuning.for_host("another-host")
assert(next(other.chat) == nil and other.inline.num_ctx == 2048)
assert(other.inline.keep_alive == "30m" and other.completion.context_window == 512)
local_profile.inline.num_ctx = 1
assert(tuning.for_host("tatooine").inline.num_ctx == 8192, "Profiles must be independent copies")

-- Exercise the AI configuration with the installed adapter's real schema
-- mapping, without loading models or contacting Ollama.
local data = vim.fn.stdpath("data") .. "/lazy/"
for _, plugin in ipairs({ "codecompanion.nvim", "plenary.nvim" }) do
  local path = data .. plugin .. "/lua/"
  package.path = path .. "?.lua;" .. path .. "?/init.lua;" .. package.path
end
package.loaded["util.ollama"] = {
  setup = function() end,
  current_model = function() return "test-model" end,
  cached_model = function() return "test-model" end,
}
package.loaded["util.copilot"] = { is_configured = function() return false end }
local captured, completion
package.loaded.codecompanion = { setup = function(opts) captured = opts end }
package.loaded.minuet = { setup = function(opts) completion = opts end }
local original_hostname = vim.uv.os_gethostname
vim.uv.os_gethostname = function() return "tatooine" end
local specs = dofile(root .. "/nvim/lua/plugins/ai.lua")
vim.uv.os_gethostname = original_hostname
for _, spec in ipairs(specs) do
  if spec[1] == "olimorris/codecompanion.nvim" or spec[1] == "milanglacier/minuet-ai.nvim" then spec.config() end
end
local adapter = captured.adapters.http.ollama_fast()
assert(adapter, "Installed Ollama adapter must load")
adapter:map_schema_to_params({ model = "test-model", num_ctx = adapter.schema.num_ctx.default,
  num_predict = adapter.schema.num_predict.default, think = false, keep_alive = adapter.schema.keep_alive.default })
assert(adapter.parameters.options.num_ctx == 8192)
assert(adapter.parameters.options.num_predict == 512)
assert(adapter.parameters.think == false and adapter.parameters.keep_alive == "10m")
assert(completion.context_window == 2048 and completion.throttle == 3000)
local options = completion.provider_options.openai_compatible.optional
assert(options.reasoning_effort == "none" and options.think == nil and options.max_tokens == 96)
print("PASS: per-host isolation and native/OpenAI-compatible request settings")
