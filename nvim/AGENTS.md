This is a Neovim configuration built on LazyVim.

Only edit files inside this directory. Do not touch files inside plugin library paths.

External tools this config expects: [DEPENDENCIES.md](DEPENDENCIES.md).

## Ollama

CodeCompanion's `ollama` adapter (`lua/plugins/ai.lua`) talks to a local Ollama
at `localhost:11434` and auto-detects **whichever model is currently loaded** —
it pins nothing. `make use-model MODEL=<tag>` in the repo root switches it, pi
and the mu agent together; `ga` in the chat buffer swaps to GitHub Copilot.

On this 8GB machine the loaded model is a 3–4B one (see the repo README for why
the tier stops there), so treat it as a fast pattern-stamper, not a reasoner.

Offload to Ollama when the task is repetitive or mechanical **and the output is
verifiable by inspection**:

- Generating lookup tables (e.g. menu key→index mappings for tests)
- Filling in boilerplate that follows an obvious pattern from one example
- Scaffolding repetitive `it()` test blocks

Write the critical scaffolding yourself; hand the stamp-out work to Ollama.

Do not offload work whose correctness you cannot check at a glance. A small
local model fails unpredictably, including on tasks that look trivial, so
"it produced something plausible" is not evidence it is right.
