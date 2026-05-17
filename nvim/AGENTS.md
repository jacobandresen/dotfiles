This is a Neovim configuration built on LazyVim.

Only edit files inside this directory. Do not touch files inside plugin library paths.

## Ollama

Ollama is running locally.


Offload to ollama whenever the task is repetitive or mechanical:

- Generating lookup tables (e.g. menu key→index mappings for tests)
- Filling in boilerplate that follows an obvious pattern from one example
- Scaffolding repetitive `it()` test blocks
- Any code generation where correctness is easy to verify by inspection

Use the `mcp__ollama__ollama_generate` tool with `model = "gemma4:latest"`. Write the critical scaffolding yourself; hand the stamp-out work to ollama.
