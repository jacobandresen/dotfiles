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

## AI

Only pi-agent is available in a terminal split. It uses Ollama's
`ministral-3:3b` model. Keep the AI menu and keymaps limited to pi.
