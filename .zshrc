export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="lambda"
zstyle ':omz:update' mode disabled # disable automatic updates
plugins=(git)
source "$ZSH/oh-my-zsh.sh"

# PATH (most-specific user bins first)
export PATH="$HOME/.local/bin:$PATH"
export PATH="PATH:$HOME/.opencode/bin:$PATH"

# Per-host development settings
[ -r "$HOME/.zshrc.dev" ] && source "$HOME/.zshrc.dev"

# Aliases
alias vim="nvim"

# Default editor (also what Midnight Commander's F4 uses, since its internal
# editor is disabled in ~/.config/mc/ini).
export EDITOR=nvim
export VISUAL=nvim

# Midnight Commander's F3 (View) uses $VIEWER when its internal viewer is off.
# Kept separate from $PAGER (less) so man/git paging is unaffected.
export VIEWER='nvim -R'

