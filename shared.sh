# shellcheck shell=sh
# shared.sh — configuration common to both bash and zsh.
#
# Sourced from both bashrc and zshrc (via ~/.shared.sh, symlinked by assimilate.sh)
# so there is a single source of truth for aliases, exports, and PATH.
# Keep this POSIX-sh compatible — it must parse under both shells.

# ----
# Exports

export LANG='en_US.UTF-8'
GPG_TTY=$(tty 2>/dev/null) || GPG_TTY=''
export GPG_TTY
export UV_MALWARE_CHECK=1
# macOS's OpenSSL PEM can lag the Homebrew CA bundle used by uv-managed Python.
# Keep an explicitly selected CA path; otherwise use the maintained public bundle.
if [ "$(uname -s)" = Darwin ] && [ "${SSL_CERT_FILE+x}" != x ]; then
  for _public_ca in /opt/homebrew/etc/ca-certificates/cert.pem /usr/local/etc/ca-certificates/cert.pem; do
    if [ -f "$_public_ca" ] && [ -r "$_public_ca" ]; then
      export SSL_CERT_FILE="$_public_ca"
      break
    fi
  done
  unset _public_ca
fi
# Keep machine-local application state outside the synchronized checkout.
export XDG_CONFIG_HOME="$HOME/.config"
# Keep gh authentication outside the checkout, independently of XDG_CONFIG_HOME.
export GH_CONFIG_DIR="$HOME/.config/gh"

# ----
# PATH
#
# Single consolidated block with a dedup helper. Move existing entries to the
# front so inherited PATH order cannot override priority in nested shells
# (e.g. tmux), where the rc files are re-sourced. Last prepend wins, so
# pinned tools in ~/.local/bin take priority over brew bottles with ABI drift.

_prepend_path() {
  _prepend_path_remaining=":$PATH:"
  while :; do
    case "$_prepend_path_remaining" in
      *":$1:"*)
        _prepend_path_remaining="${_prepend_path_remaining%%":$1:"*}:${_prepend_path_remaining#*":$1:"}"
        ;;
      *) break ;;
    esac
  done
  PATH="$1${_prepend_path_remaining%:}"
  unset _prepend_path_remaining
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
# Socket Firewall: interactive package-manager commands use the guarded launcher.
# Socket Free sends mandatory telemetry; custom/private registries are unsupported.
# Aliases do not alter executable files or wrap scripts/absolute-path invocations.
# Bun is not officially guaranteed by Socket; keep its own age/lock/script controls.
if [ -x "$HOME/.local/bin/sfw" ]; then
  alias npm='"$HOME/.local/bin/sfw" npm'
  alias bun='"$HOME/.local/bin/sfw" bun'
  alias uv='"$HOME/.local/bin/sfw" uv'
fi

# ----
# Aliases

# general
alias vi=nvim
alias vim=nvim
command -v lsd >/dev/null 2>&1 && alias ls="lsd -al"
# shellcheck disable=SC2139 # Resolve this explicit trusted HOME path when sourced.
alias claude="$HOME/.local/bin/claude"

# Docker
alias d='docker'
alias dc='docker compose'
alias dcup='docker compose up'
alias dsp='docker system prune --all --force'
alias docker_rmi_dangling='docker rmi $(docker images -qa -f "dangling=true") -f'

# python
# python and python3 resolve to uv's ~/.local/bin executables.
alias pip='uv pip'
alias pip3='uv pip'
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
