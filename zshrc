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
  PROMPT="%F{yellow}[%m]%f $PROMPT"
else
  export EDITOR='nvim'
fi

export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"

# zsh-autosuggestions (installed via brew on macOS, may be missing elsewhere)
if command -v brew >/dev/null 2>&1; then
  _zsh_autosug="$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  [ -f "$_zsh_autosug" ] && source "$_zsh_autosug"
  unset _zsh_autosug
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
alias snowsql=/Applications/SnowSQL.app/Contents/MacOS/snowsql

# The next line updates PATH for the Google Cloud SDK.
if [ -f "$HOME/Downloads/google-cloud-sdk/path.zsh.inc" ]; then . "$HOME/Downloads/google-cloud-sdk/path.zsh.inc"; fi

# The next line enables shell command completion for gcloud.
if [ -f "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc" ]; then . "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc"; fi

# .zsh syntax highlighting (installed via brew on macOS, may be missing elsewhere)
if [ -f /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
  source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# Prepend so pinned overrides in assimilate.sh (e.g. delta) win over brew bottles with ABI drift
export PATH="$HOME/.local/bin:$PATH"

autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /opt/homebrew/bin/terraform terraform

fpath+=~/.zfunc; autoload -Uz compinit; compinit

zstyle ':completion:*' menu select

# Send escape sequence for vertical bar for proper cursor reset with nvim + tmux + ghostty
_reset_cursor() { printf '\e[6 q' }
precmd_functions+=(_reset_cursor)


# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
