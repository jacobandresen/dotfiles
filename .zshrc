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

# Per-host LLM tuning for the mu agent. The mu repo's `make setup-host` probes
# the GPU and writes ~/.zshrc.mu (machine-local, outside this repo) with
# MU_AGENT_MODEL / MU_NUM_CTX. Sourced if present; absent on a fresh host, where
# mu's own defaults apply.
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
