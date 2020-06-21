export ZSH="/Users/lexokan/.oh-my-zsh"
export UPDATE_ZSH_DAYS=13

# Match hidden files with tab
setopt globdots

ZSH_THEME="robbyrussell"

CASE_SENSITIVE="false"
HYPHEN_INSENSITIVE="true"

DISABLE_AUTO_UPDATE="false"
DISABLE_UPDATE_PROMPT="false"
DISABLE_LS_COLORS="false"
DISABLE_UNTRACKED_FILES_DIRTY="false"
DISABLE_AUTO_TITLE="false"
DISABLE_MAGIC_FUNCTIONS=false

ENABLE_CORRECTION="true"
HIST_STAMPS="mm/dd/yyyy"
COMPLETION_WAITING_DOTS="false"

# Plugins
plugins=(git)

source $ZSH/oh-my-zsh.sh

# User configuration
# Preferred editor for local and remote sessions
 if [[ -n $SSH_CONNECTION ]]; then
   export EDITOR='vim'
 else
   export EDITOR='nvim'
 fi

# Aliases
alias vi=nvim
alias python=python3
alias config='/usr/bin/git --git-dir=/Users/lexokan/.cfg/ --work-tree=/Users/lexokan'

alias jpn='jupyter notebook'

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

# PySpark config
export HADOOP_HOME=~/spark/hadoop-2.7.7
export PATH=$PATH:~/spark/hadoop-2.7.7/bin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HADOOP_HOME/lib/native
export HADOOP_OPTS="$HADOOP_OPTS -Djava.library.path=$HADOOP_HOME/lib/native"

export SPARK_HOME=~/spark/spark-2.4.5-bin-hadoop2.7
export PATH=$PATH:~/spark/spark-2.4.5-bin-hadoop2.7/bin

export PYTHONPATH=$SPARK_HOME/python:$SPARK_HOME/python/lib/py4j-0.10.7-src.zip:$PYTHONPATH
export PYTHONPATH=$SPARK_HOME/python:$SPARK_HOME/python/:$PYTHONPATH
export PATH=$PATH:${SPARK_HOME}/python

export PYSPARK_DRIVER_PYTHON=jupyter
export PYSPARK_DRIVER_PYTHON_OPTS='notebook'

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/Users/lexokan/miniconda3/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/Users/lexokan/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/Users/lexokan/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/Users/lexokan/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

