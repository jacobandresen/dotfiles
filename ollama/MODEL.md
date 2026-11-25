# Local coding model

Pi uses JetBrains Mellum 2.1 (`mellum`) through Ollama by default. Qwen 3.5 9B
remains available as an alternative. `make use-model` pulls Mellum if needed,
keeps it loaded, and configures pi-agent to use it.

One request at a time gets the full 32K context; extra requests queue behind
it. Neovim also allows three active task agents by default; they take turns.
The model only partly fits in 6 GB VRAM, so `ollama/ollama.service.d/override.conf`
keeps it resident in RAM (`MemorySwapMax=1G`) and `ollama/ollama.sysctl` lowers
`vm.swappiness` to 5 — a swapped-out expert page costs seconds per token.
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

## Neovim inline autocomplete

Neovim (minuet-ai.nvim, ghost text via `<A-a>` to accept) uses a separate small
FIM model: `qwen2.5-coder:1.5b-base`, served by the same Ollama instance. Its
built-in template passes the fill-in-the-middle tokens through, so completions
stay code-only. `make use-model` pulls it and keeps both models resident
(`OLLAMA_MAX_LOADED_MODELS=2`); without that, Mellum and qwen evict each other
and every suggestion pays a full model load. Tuning lives in
`nvim/lua/plugins/ai.lua`: 100 ms debounce, 250 ms throttle, 48-token cap,
streaming, and a 2048-character context window around the cursor.
