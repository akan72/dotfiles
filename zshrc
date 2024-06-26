# Basics
source ~/.bashrc

export ZSH="$HOME/.oh-my-zsh"
export UPDATE_ZSH_DAYS=13

# Match hidden files with tab
setopt globdots

# User Settings
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
plugins=(
  git
)

bindkey -e
bindkey "^[begin" backward-word
bindkey "^[end" forward-word

bindkey "^[endline" end-of-line
bindkey "^[beginline" beginning-of-line

source $ZSH/oh-my-zsh.sh

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='nvim'
fi

export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"
source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
