# shared.sh — configuration common to both bash and zsh.
#
# Sourced from both bashrc and zshrc (via ~/.shared.sh, symlinked by assimilate.sh)
# so there is a single source of truth for aliases, exports, and PATH.
# Keep this POSIX-sh compatible — it must parse under both shells.

# ----
# Exports

export LANG='en_US.UTF-8'
export GPG_TTY=$(tty)
export UV_MALWARE_CHECK=1
# $XDG_CONFIG_HOME drives Zed and Ghostty config discovery
export XDG_CONFIG_HOME="$HOME/dotfiles"

# ----
# PATH
#
# Single consolidated block with a dedup helper. Prepending through this guard
# keeps PATH from ballooning with duplicates in nested shells (e.g. tmux), where
# the rc files are re-sourced. Last prepend wins (ends up first on PATH), so
# pinned tools in ~/.local/bin take priority over brew bottles with ABI drift.

_prepend_path() {
  case ":$PATH:" in
    *":$1:"*) ;;          # already present — skip
    *) PATH="$1:$PATH" ;;
  esac
}

_prepend_path "/usr/local/bin"                          # Homebrew (Intel)
_prepend_path "/opt/homebrew/bin"                       # Homebrew (ARM/M1)
# Postgres — guarded so shells without Homebrew (e.g. the Linux dev box) don't
# error on every startup
if command -v brew >/dev/null 2>&1; then
  _prepend_path "$(brew --prefix postgresql@17)/bin"
fi
_prepend_path "$HOME/.yarn/bin"                         # Yarn global bins
_prepend_path "$HOME/.config/yarn/global/node_modules/.bin"
export BUN_INSTALL="$HOME/.bun"
_prepend_path "$BUN_INSTALL/bin"                        # Bun
_prepend_path "$HOME/.local/bin"                        # pinned tools (delta, claude, uv)
export PATH

# ----
# Aliases

# general
alias vi=nvim
alias vim=nvim
command -v lsd >/dev/null 2>&1 && alias ls="lsd -al"
alias claude="$HOME/.local/bin/claude"

# Docker
alias d='docker'
alias dc='docker compose'
alias dcup='docker compose up'
alias dsp='docker system prune --all --force'
alias docker_rmi_dangling='docker rmi $(docker images -qa -f "dangling=true") -f'

# python
alias python='python3.11'
alias python3='python3.11'
alias pip='python3.11 -m pip'
alias pip3='pip'
alias grepy='grep -r --include \*.py'
alias greps='grep -r --include \*.sql'
alias jpn='jupyter notebook'
ver() {
    pip list | grep "$1"
}

# git
alias g='git status'
alias gs='git status'
alias gf='git fetch'
alias gm='git merge'
alias ga='git add'
alias gb='git branch'
alias gc='git commit'
alias gck='git checkout'
alias gckb='git checkout -b'
alias gd='git diff'
alias gg='git grep'
alias gl='git log --reverse -n 10'
alias gpl='git pull'
alias gp='git push'
alias gdm='git diff main'
alias gdnm='git diff --name-only origin/main'
alias gcap='git checkout main && git pull'

# kube
alias ku='kubectl'
alias kuc='kubectl config'

# dbt
alias docs="dbt docs generate; dbt docs serve"
alias dbtb="dbt build"
alias dbtc="dbt compile"
alias dbtr="dbt run"

# rust
alias cb="cargo build"
alias cr="cargo run"
alias ct="cargo test"

# modal
alias md="modal deploy"
alias mr="modal run"

# terraform
alias tf="terraform"
