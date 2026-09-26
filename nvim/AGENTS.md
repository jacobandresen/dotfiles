This is a Neovim configuration built on LazyVim.

Only edit files inside this directory. Do not touch files inside plugin library paths.

External tools this config expects: [DEPENDENCIES.md](DEPENDENCIES.md).

## Turbo Vim look

The UI imitates the Borland Turbo Pascal 7.0 IDE: `colors/turbopascal.lua`
(EGA palette) and `lua/turbo/` (menu bar in the tabline, hint line in the
statusline, window title frames in the winbar, About dialog). lualine and
bufferline are disabled for it. Menu entries live in `lua/turbo/menus.lua`,
grouped by task (≡, File, Edit, Search, Code, Run, Debug, AI, Tools, Window,
Help) with cascading submenus (►, one level deep); the Turbo Vision look and
TP's F-keys stay, TP7's menu names don't have to. Only entries with a working
Neovim equivalent (no greyed-out placeholders); every key shown in a menu
exists as a keymap; an action used in the wrong context explains itself with a
notification, not a raw Vim error. The matching Midnight Commander skin is `../mc/skins/turbopascal.ini`.

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
