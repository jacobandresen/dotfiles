This is a Neovim configuration built on LazyVim.

Only edit files inside this directory. Do not touch files inside plugin library paths.

External tools this config expects: [DEPENDENCIES.md](DEPENDENCIES.md).

## Turbo Vim look

The UI imitates the Borland Turbo Pascal 7.0 IDE: `colors/turbopascal.lua`
(EGA palette) and `lua/turbo/` (menu bar in the tabline, hint line in the
statusline, window title frames in the winbar, About dialog). lualine and
bufferline are disabled for it. Menu entries live in `lua/turbo/menus.lua`:
TP7 entry names, but only those with a working Neovim equivalent (no greyed-out
placeholders). Tools that TP never had (Docker, AI, Database) are Tools transfer
items, one cascading submenu (►) each; every item there shows its `<leader>`
shortcut, and every such shortcut exists as a keymap. Menu actions called in the
wrong context should explain themselves with a notification, not a raw Vim
error. The matching Midnight Commander skin is `../mc/skins/turbopascal.ini`.

## Ollama

CodeCompanion's `ollama` adapter and Minuet's inline suggestions
(`lua/plugins/ai.lua`, sharing `lua/util/ollama.lua`) talk to a local Ollama at
`localhost:11434` and auto-detect **whichever model is currently loaded** —
neither pins one. `make use-model MODEL=<tag>` in the repo root switches it, pi
and the mu agent together; `ga` in the chat buffer swaps to GitHub Copilot.

Offload to Ollama when the task is repetitive or mechanical **and the output is
verifiable by inspection**:

- Generating lookup tables (e.g. menu key→index mappings for tests)
- Filling in boilerplate that follows an obvious pattern from one example
- Scaffolding repetitive `it()` test blocks

Write the critical scaffolding yourself; hand the stamp-out work to Ollama.

Do not offload work whose correctness you cannot check at a glance. A small
local model fails unpredictably, including on tasks that look trivial, so
"it produced something plausible" is not evidence it is right.
