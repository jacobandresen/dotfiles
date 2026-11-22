# Local coding model

Pi uses JetBrains Mellum 2.1 (`mellum`) through Ollama by default. Qwen 3.5 9B
remains available as an alternative. `make use-model` pulls Mellum if needed,
keeps it loaded, and configures pi-agent to use it.

Ollama allows three concurrent requests sharing one loaded model, with a 16K
context per request and a 20G memory soft limit. Neovim also allows three active
task agents by default. Mellum runs on CPU here, so concurrent tasks share CPU
capacity and may each respond more slowly.
Thinking is off by default for Mellum (`modelThinkingLevels` in
`pi/agent/settings.json.template`): pi sends `reasoning_effort: "none"` and
`ollama/Mellum.Modelfile` answers that with an empty think block, so replies
start immediately and no reasoning leaks into the answer. The upstream template
always opened `<think>` and ignored the request. Select a thinking level in pi
(for example `low` or `high`) when a task needs it; that level is sent as
`reasoning_effort` and re-enables thinking. `make use-model` rebuilds
`mellum` from the Modelfile when the installed template is outdated.

Warmup uses an empty chat request to preload the model without generating tokens
or occupying a task slot.
