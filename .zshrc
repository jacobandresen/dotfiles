export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="lambda"
zstyle ':omz:update' mode disabled # disable automatic updates
plugins=(git)
source "$ZSH/oh-my-zsh.sh"

# PATH (most-specific user bins first)
export PATH="$HOME/.local/bin:$PATH"
export PATH="$PATH:$HOME/.lmstudio/bin"

# Per-host development settings
[ -r "$HOME/.zshrc.dev" ] && source "$HOME/.zshrc.dev"

# Per-host hardware tuning. scripts/setup-host.sh probes the GPU and writes
# ~/.zshrc.mu (machine-local, outside the repo) with MU_NUM_CTX. Sourced
# *before* the default below so a bigger card's value wins; absent on a
# fresh/default host, where the committed default applies.
[ -r "$HOME/.zshrc.mu" ] && source "$HOME/.zshrc.mu"

# Aliases
alias vim="nvim"

# Default editor (also what Midnight Commander's F4 uses, since its internal
# editor is disabled in ~/.config/mc/ini).
export EDITOR=nvim
export VISUAL=nvim

# Midnight Commander's F3 (View) uses $VIEWER when its internal viewer is off.
# Kept separate from $PAGER (less) so man/git paging is unaffected.
export VIEWER='nvim -R'
