This is a Neovim configuration built on LazyVim with a local turbovim plugin.

Only edit files inside this directory. Do not touch files inside plugin library paths.

## Tests

Any change to turbovim (menus, keymaps, adapters, navigation) must leave the full test suite green.

Run from `dev/turbovim/`:

```sh
make test
```

All 161 tests must pass before a change is considered complete. If you add a menu entry, update the count in `menu_spec.lua` and the `alt_keys` table in `keymaps_spec.lua`. If you change an action, add or update the corresponding assertion in `ai_spec.lua` or the relevant spec.

## Ollama

Ollama is running locally with the following models:

- `gemma4:latest` — primary local model, good at code and structured data
- `gemma3:4b` — smaller/faster fallback

Offload to ollama whenever the task is repetitive or mechanical:

- Generating lookup tables (e.g. menu key→index mappings for tests)
- Filling in boilerplate that follows an obvious pattern from one example
- Scaffolding repetitive `it()` test blocks
- Any code generation where correctness is easy to verify by inspection

Use the `mcp__ollama__ollama_generate` tool with `model = "gemma4:latest"`. Write the critical scaffolding yourself; hand the stamp-out work to ollama.

## Dependency checks

Before declaring a setup change done, run:

```sh
./check-deps.sh
```

All entries should show `[OK]`. Missing entries mean `setup.sh` needs updating.
