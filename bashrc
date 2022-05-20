# ----
# Basics

set -o vi

export EDITOR='nvim'
export TERM='xterm-256color'
export LANG='en_US.UTF-8'

# ----
# Aliases

# general
alias config='/usr/bin/git --git-dir=/Users/lexokan/.cfg/ --work-tree=/Users/lexokan'
alias vi=nvim
alias vim=nvim
alias d=docker
alias dc=docker-compose

# python
alias python='python3.9'
alias pip='pip3'
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
alias gd='git diff'
alias gca='git commit -a'
alias gcm='git commit -m'
alias gcam='git commit -am'
alias gcaa='git commit -a --amend -C HEAD'
alias gg='git grep'
alias glo='git log'
alias gl='git pull'
alias gp='git push'

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
alias k='kubectl'
alias kc='kubectl config'

# ---
# Applications

# flask
export FLASK_APP=src/app/__init__.py
export FLASK_ENV=development

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# anaconda
export PATH="$HOME/opt/anaconda3/bin:$PATH"

# sops
export PATH="$PATH:~/Downloads/sops-3.7.2"

