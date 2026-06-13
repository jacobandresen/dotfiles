export ZSH="$HOME/.oh-my-zsh"

# PATH (most-specific user bins first)
export PATH="$HOME/Env/Python/pygame/bin:$PATH"
export PATH="/opt/npm-global/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export PATH="$PATH:$HOME/.lmstudio/bin"

# oh-my-zsh: keep plugins, but no theme -- we set a DOS prompt below.
ZSH_THEME=""
zstyle ':omz:update' mode disabled # disable automatic updates
plugins=(git)
source "$ZSH/oh-my-zsh.sh"

# Commodore 64-style prompt: BASIC printed READY. and left you on a fresh line
# with a blinking block cursor -- no path, no prefix. Type right there.
PROMPT=$'READY.\n'
RPROMPT=''


# Aliases
alias vim="nvim"
alias pi='command pi --tools read,write,edit,bash'

# Default editor (also what Midnight Commander's F4 uses, since its internal
# editor is disabled in ~/.config/mc/ini).
export EDITOR=nvim
export VISUAL=nvim

# Midnight Commander's F3 (View) uses $VIEWER when its internal viewer is off.
# Kept separate from $PAGER (less) so man/git paging is unaffected.
export VIEWER='nvim -R'

# Commodore 64-style boot banner, with the real OS name + RAM.
#   **** ARCH LINUX ****   (or UBUNTU / MACOS)
#   *** TAARNBY KODEHULE, 2026 ***
#    <total>G RAM SYSTEM  <free> MB FREE
_c64_boot() {
  local os ram_total ram_free
  if [[ "$(uname -s)" == "Darwin" ]]; then
    os="MACOS"
    ram_total=$(( ($(sysctl -n hw.memsize) + 536870912) / 1073741824 ))      # GiB, rounded
    local pgsize free_pages
    pgsize=$(sysctl -n hw.pagesize)
    free_pages=$(vm_stat | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')
    ram_free=$(( free_pages * pgsize / 1048576 ))                            # MiB
  else
    if [[ -r /etc/os-release ]]; then
      os=$( . /etc/os-release; echo "${NAME}" )                             # "Arch Linux", "Ubuntu", ...
    else
      os="LINUX"
    fi
    ram_total=$(( ($(awk '/MemTotal/{print $2}' /proc/meminfo) + 524288) / 1048576 ))  # GiB, rounded
    ram_free=$(( $(awk '/MemAvailable/{print $2}' /proc/meminfo) / 1024 ))             # MiB
  fi
  os=${(U)os}
  print -r -- ""
  print -r -- "    **** ${os} ****"
  print -r -- "   *** TAARNBY KODEHULE, 2026 ***"
  print -r -- ""
  print -r -- " ${ram_total}G RAM SYSTEM  ${ram_free} MB FREE"
  print -r -- ""
  # No "READY." here -- the prompt prints it, so startup shows it only once.
}
_c64_boot


