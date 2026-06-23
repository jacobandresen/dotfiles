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
# ~/.zshrc.local (machine-local, outside the repo) with MU_NUM_CTX. Sourced
# *before* the default below so a bigger card's value wins; absent on a
# fresh/default host, where the committed default applies.
[ -r "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"

# Right side: a minimal cwd and the current git branch, kept dim so the READY.
# prompt stays the focus. vcs_info fills in the branch (and rebase/merge state)
# before each prompt. %(4~|…/%3~|%~) shows the full home-relative path but trims
# deep ones to their last three components. %F{8} = dim grey, %F{6} = cyan.
setopt prompt_subst
autoload -Uz add-zsh-hook vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats       ' %F{6}(%b)%f'
zstyle ':vcs_info:git:*' actionformats ' %F{6}(%b|%a)%f'
add-zsh-hook precmd vcs_info
RPROMPT='%F{8}%(4~|…/%3~|%~)%f${vcs_info_msg_0_}'

# Aliases
alias vim="nvim"

# Default editor (also what Midnight Commander's F4 uses, since its internal
# editor is disabled in ~/.config/mc/ini).
export EDITOR=nvim
export VISUAL=nvim

# Midnight Commander's F3 (View) uses $VIEWER when its internal viewer is off.
# Kept separate from $PAGER (less) so man/git paging is unaffected.
export VIEWER='nvim -R'
