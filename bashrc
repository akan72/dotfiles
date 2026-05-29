# ----
# Basics

set -o vi

export LANG='en_US.UTF-8'

# Ask uv to check resolved packages against malicious-package advisories.
export UV_MALWARE_CHECK=1

# ----
# Aliases

# general
alias vi=nvim
alias vim=nvim
# lsd comes from the Brewfile on macOS; guard so a Linux box without it keeps
# a working `ls`
command -v lsd >/dev/null 2>&1 && alias ls="lsd -al"

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
function ver {
    pip list | grep $1
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

# ---
# Applications

# Homebrew
# Intel Path
export PATH="/usr/local/bin:${PATH}"

# ARM/M1 Path
export PATH="/opt/homebrew/bin:${PATH}"

# Postgres
export PATH="$(brew --prefix postgresql@17)/bin:${PATH}"

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

# GPG
export GPG_TTY=$(tty)

# Terraform
alias tf="terraform"
if [ -n "$BASH_VERSION" ]; then
  complete -C /opt/homebrew/bin/terraform terraform
fi

# Set $XDG_CONFIG_HOME for Zed and Ghostty
export XDG_CONFIG_HOME="$HOME/dotfiles"

# Claude
alias claude="$HOME/.local/bin/claude"
