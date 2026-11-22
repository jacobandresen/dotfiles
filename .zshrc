export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="awesomepanda"
zstyle ':omz:update' mode disabled # disable automatic updates
plugins=(git)
if [ -r "$ZSH/oh-my-zsh.sh" ]; then
  source "$ZSH/oh-my-zsh.sh"
else
  print -u2 "Oh My Zsh is missing; run make deps in your dotfiles directory."
fi

# PATH (most-specific user bins first)
export PATH="$HOME/.local/bin:$PATH"

# Issue worktrees + pi. Use `git-pi start <issue>` in one terminal tab per issue.
alias gdiff='git-pi diff'
alias gwt='git-pi list'

# Per-host development settings
[ -r "$HOME/.zshrc.dev" ] && source "$HOME/.zshrc.dev"

# On macOS, `make install-ollama` writes ~/.ollama/dotfiles.env from ollama/ollama.env.
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
