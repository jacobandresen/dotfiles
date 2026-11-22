# Local coding model

Pi uses JetBrains Mellum 2.1 (`mellum`) through Ollama by default. Qwen 3.5 9B
remains available as an alternative. `make use-model` pulls Mellum if needed,
keeps it loaded, and configures pi-agent to use it.

Ollama allows three concurrent requests sharing one loaded model, with a 16K
context per request and a 20G memory soft limit. Neovim also allows three active
task agents by default. Mellum runs on CPU here, so concurrent tasks share CPU
capacity and may each respond more slowly.
Warmup uses an empty chat request to preload the model without generating tokens
or occupying a task slot.
