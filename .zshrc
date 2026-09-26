export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="lambda"
zstyle ':omz:update' mode disabled # disable automatic updates
plugins=(git)
source "$ZSH/oh-my-zsh.sh"

# In kitty (kitty/kitty.conf: MS-DOS text screen) use a DOS prompt, e.g.
# C:\HOME\JACOB> - KITTY_WINDOW_ID is inherited by tmux inside kitty too.
if [ -n "$KITTY_WINDOW_ID" ]; then
  PROMPT='C:${(U)PWD//\//\\}>'
  RPROMPT=''
fi

# PATH (most-specific user bins first)
export PATH="$HOME/.local/bin:$PATH"

# Per-host development settings
[ -r "$HOME/.zshrc.dev" ] && source "$HOME/.zshrc.dev"

# Per-host Ollama tuning. `make install-ollama` writes ~/.ollama/dotfiles.env
# from the RAM profile in ollama/launchd/ (machine-local, outside this repo) so
# a shell-launched `ollama serve` gets the same limits as the menubar app.
[ -r "$HOME/.ollama/dotfiles.env" ] && source "$HOME/.ollama/dotfiles.env"


# Aliases
alias vim="nvim"

# Default editor (also what Midnight Commander's F4 uses, since its internal
# editor is disabled in ~/.config/mc/ini).
export EDITOR=nvim
export VISUAL=nvim

# Midnight Commander's F3 (View) uses $VIEWER when its internal viewer is off.
export VIEWER='nvim -R'
# Kept separate from $PAGER (less) so man/git paging is unaffected.
