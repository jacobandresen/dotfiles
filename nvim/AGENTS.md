This is a Neovim configuration built on LazyVim.

Only edit files inside this directory. Do not touch files inside plugin library paths.

External tools this config expects: [DEPENDENCIES.md](DEPENDENCIES.md).

## Turbo Vim look

The UI imitates the Borland Turbo Pascal 7.0 IDE: `lua/turbo/` (menu bar in the tabline, hint line in the
statusline, window title frames in the winbar, About dialog). lualine and
bufferline are disabled for it. Menu entries live in `lua/turbo/menus.lua`,
grouped by task (File, Edit, Search, Code, Debug, AI, Tools, Window,
Help) with cascading submenus (►, one level deep); the Turbo Vision look
stays, TP7's menu names don't have to. Keys: plain and Shift+F1–F10, Alt+letter
and Space chords only — never Ctrl+F-keys, Alt+F-keys or Alt+Space, which
GNOME/KDE take first (see `lua/turbo/init.lua`). Only entries with a working
Neovim equivalent (no greyed-out placeholders); every key shown in a menu
exists as a keymap; an action used in the wrong context explains itself with a
notification, not a raw Vim error. 

Colours: the default scheme is Neovim's built-in `retrobox`;
`lua/turbo/highlights.lua` gives the Turbo chrome gruvbox tones under it (and
derives them for any other scheme). `colors/turbopascal.lua` is the full blue
EGA screen. Matching Midnight Commander skins: `../mc/skins/retrobox.ini`
(default) and `../mc/skins/turbopascal.ini`.

## Ollama

Neovim has no Ollama client of its own: pi, Claude Code and Codex run in terminal
splits (`lua/util/agents.lua`). Preserve the server RAM/OS profiles in `../ollama/`.

For AI runtime behavior, see [DEPENDENCIES.md](DEPENDENCIES.md#ai-luapluginsaelua).

Offload to Ollama when the task is repetitive or mechanical **and the output is
verifiable by inspection**:

- Generating lookup tables (e.g. menu key→index mappings for tests)
- Filling in boilerplate that follows an obvious pattern from one example
- Scaffolding repetitive `it()` test blocks

Write the critical scaffolding yourself; hand the stamp-out work to Ollama.

Do not offload work whose correctness you cannot check at a glance. A small
local model fails unpredictably, including on tasks that look trivial, so
"it produced something plausible" is not evidence it is right.
