# ----
# Basics

set -o vi

export EDITOR='nvim'
export TERM='xterm-256color'
export LANG='en_US.UTF-8'

# ----
# Aliases

# general
alias config="/usr/bin/git --git-dir=/Users/${USER}/.cfg/ --work-tree=/Users/${USER}"
alias vi=nvim
alias vim=nvim

# Docker
alias d='docker'
alias dc='docker compose'
alias dcup='docker compose up'
alias docker_rmi_dangling='docker rmi $(docker images -qa -f 'dangling=true') -f'

# python
alias python='python3.10'
alias python3='python3.10'
alias pip='python3.10 -m pip'
alias grepy='grep -r --include \*.py'
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
alias gd='git difftool'
alias gca='git commit -a'
alias gcm='git commit -m'
alias gcam='git commit -am'
alias gcaa='git commit -a --amend -C HEAD'
alias gg='git grep'
alias glo='git log'
alias gl='git pull'
alias gp='git push'
alias gdm='git diff master'
alias gdnm='git diff --name-only master'

# hg
alias hs='hg status'
alias hc='hg commit'
alias ha='hg amend'
alias hd='hg diff'
alias hl='hg log'
alias hu='hg update'
alias hp='hg prev'
alias hn='hg next'
alias ht='hg top'
alias hb='hg bottom'

# kube
alias ku='kubectl'
alias kuc='kubectl config'

# ---
# Applications

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# sops
export PATH="$PATH:~/Downloads/sops-3.7.2"

# Homebrew
# Intel Path
export PATH="/usr/local/bin:${PATH}"

# ARM/M1 Path
export PATH="/opt/homebrew/bin:${PATH}"

