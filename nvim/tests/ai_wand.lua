-- Run: NVIM_LOG_FILE=/tmp/nvim-wand.log nvim --headless -u NONE -i NONE -l nvim/tests/ai_wand.lua
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local api = vim.api
local wand = require("util.ai_wand")
wand.setup()
local adapter = {
  name = "copilot", formatted_name = "Copilot", opts = { stream = true },
  map_schema_to_params = function(self, settings) self.settings = settings return self end,
}
local chat = { adapter = adapter, settings = { model = "chosen-model", temperature = 0.1 } }
local sent, callbacks, resolved, cancelled, used_adapter
package.loaded.codecompanion = { last_chat = function() return chat end }
package.loaded["codecompanion.adapters"] = {
  resolve = function(name)
    resolved = name
    return vim.tbl_extend("force", adapter, { name = name })
  end,
  call_handler = function(_, _, data) return { status = "success", output = { content = data } } end,
}
package.loaded["codecompanion.adapters.utils"] = { resolve_model = function(a) return a.settings and a.settings.model or "local-model" end }
package.loaded["codecompanion.http"] = {
  new = function(args)
    used_adapter = args.adapter
    return { send = function(_, payload, opts)
      sent = payload
      callbacks = opts
      return { cancel = function() cancelled = true end }
    end }
  end,
}
local diagnostic_ns = api.nvim_create_namespace("wand_test")
local function source()
  local buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "lua"
  api.nvim_buf_set_lines(buf, 0, -1, false, { "local x = nil", "print(x.name)", "print('unchanged')" })
  vim.diagnostic.set(diagnostic_ns, buf, {
    { lnum = 1, col = 6, end_col = 7, severity = vim.diagnostic.severity.ERROR, source = "test-lsp", message = "x may be nil" },
  })
  api.nvim_win_set_cursor(0, { 2, 6 })
  return buf
end
local function reply(original, replacement)
  callbacks.on_chunk(vim.json.encode({ original = original, replacement = replacement }))
  callbacks.on_done()
end
local function event(name, data) api.nvim_exec_autocmds("User", { pattern = name, data = data }) end
local function available()
  for _, menu in ipairs(require("turbo.menus").menus) do
    if menu.title == "~C~ode" then
      for _, item in ipairs(menu.items()) do
        if type(item) == "table" and item.key == "Space c w" then return true end
      end
    end
  end
  return false
end
assert(available())
event("CodeCompanionRequestStarted", { id = "chat1" })
assert(wand.busy() and not available())
wand.fix()
assert(sent == nil)
event("CodeCompanionRequestFinished", { id = "chat1" })
assert(not wand.busy())
event("MinuetRequestStartedPre", { timestamp = 12, n_requests = 2 })
event("MinuetRequestFinished", { timestamp = 12 })
assert(wand.busy())
event("MinuetRequestFinished", { timestamp = 12 })
assert(not wand.busy())
local buf = source()
wand.fix()
assert(wand.busy() and not available())
assert(used_adapter.name == "copilot" and used_adapter.settings.model == "chosen-model")
assert(adapter.settings == nil, "Do not mutate the chat adapter")
local context = vim.json.decode(sent.messages[2].content)
assert(context.diagnostic.message == "x may be nil" and context.filetype == "lua")
assert(sent.messages[1].content:find("Do not suppress diagnostics", 1, true))
local first_callbacks = callbacks
wand.fix()
assert(callbacks == first_callbacks, "One fix at a time")
reply("print(x.name)", "if x then print(x.name) end")
assert(not wand.busy() and available())
assert(api.nvim_buf_get_lines(buf, 1, 2, false)[1] == "if x then print(x.name) end")
assert(vim.bo[buf].modified)
assert(api.nvim_buf_get_lines(buf, 2, 3, false)[1] == "print('unchanged')")
-- Concurrent edits must survive, and the late AI response stays visible.
buf = source()
wand.fix()
api.nvim_buf_set_lines(buf, 0, 1, false, { "local x = {}" })
reply("print(x.name)", "print(x and x.name)")
assert(not wand.busy())
assert(api.nvim_buf_get_lines(buf, 1, 2, false)[1] == "print(x.name)")
assert(table.concat(api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("Code changed", 1, true))
-- Cancellation prevents callbacks from applying a late result.
buf = source()
wand.fix()
local stop = vim.fn.maparg("q", "n", false, true).callback
stop()
assert(cancelled and not wand.busy())
reply("print(x.name)", "print(x and x.name)")
assert(api.nvim_buf_get_lines(buf, 1, 2, false)[1] == "print(x.name)")
-- An error releases the lock; no chat falls back to Ollama.
buf = source()
chat = nil
wand.fix()
assert(resolved == "ollama")
callbacks.on_error({ message = "test error" })
assert(not wand.busy())
-- Closing the progress buffer cancels work and releases the lock.
buf = source()
wand.fix()
api.nvim_buf_delete(0, { force = true })
assert(not wand.busy())
api.nvim_set_current_buf(buf)
-- Invalid, ambiguous and unrelated edits cannot change source.
local tick = api.nvim_buf_get_changedtick(buf)
for _, edit in ipairs({
  "not json",
  vim.json.encode({ original = "print", replacement = "warn" }),
  vim.json.encode({ original = "local x = nil", replacement = "local x = {}" }),
  vim.json.encode({ original = "missing", replacement = "anything" }),
}) do
  assert(not wand.apply(buf, tick, 0, 3, 1, edit))
  assert(api.nvim_buf_get_changedtick(buf) == tick)
end
-- Multiple overlapping diagnostics require choosing one.
api.nvim_set_current_buf(buf)
api.nvim_win_set_cursor(0, { 2, 6 })
vim.diagnostic.set(diagnostic_ns, buf, {
  { lnum = 1, col = 6, end_col = 7, message = "first" },
  { lnum = 1, col = 6, end_col = 7, message = "second" },
})
vim.ui.select = function(items, _, choose) assert(#items == 2) choose(items[2]) end
wand.fix()
assert(vim.json.decode(sent.messages[2].content).diagnostic.message == "second")
callbacks.on_error({ message = "done" })
print("Wand selection, adapter, context, locking, application and cancellation passed")
