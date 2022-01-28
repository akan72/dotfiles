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
alias d=docker
alias dc=docker-compose

# python
alias python='python3.8'
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

# ---
# Applications

# pyspark
export HADOOP_HOME=~/spark/hadoop-2.7.7
export PATH=$PATH:~/spark/hadoop-2.7.7/bin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HADOOP_HOME/lib/native
export HADOOP_OPTS="$HADOOP_OPTS -Djava.library.path=$HADOOP_HOME/lib/native"

export SPARK_HOME=~/spark/spark-3.0.0-bin-hadoop2.7
export PATH=$PATH:~/spark/spark-3.0.0-bin-hadoop2.7/bin

export PYTHONPATH=$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.7-src.zip:$PYTHONPATH
export PYTHONPATH=$SPARK_HOME/python:$SPARK_HOME/python/:$PYTHONPATH
export PATH=$PATH:${SPARK_HOME}/python

export PYSPARK_DRIVER_PYTHON=jupyter
export PYSPARK_DRIVER_PYTHON_OPTS='notebook'

# airflow
export AIRFLOW_HOME=~/airflow

# flask
export FLASK_APP=src/app/__init__.py
export FLASK_ENV=development

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

