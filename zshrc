# Basics
# bashrc is no longer sourced from zshrc (bash-specific syntax can break under zsh).
# The shared aliases/exports below are inlined here; a follow-up extracts them to shared.sh.

export LANG='en_US.UTF-8'
export XDG_CONFIG_HOME="$HOME/dotfiles"
export GPG_TTY=$(tty)

# Homebrew (Intel + ARM) PATH
export PATH="/usr/local/bin:${PATH}"
export PATH="/opt/homebrew/bin:${PATH}"
# Postgres
export PATH="$(brew --prefix postgresql@17)/bin:${PATH}"

# Aliases — general
alias vi=nvim
alias vim=nvim
alias ls="lsd -al"
alias claude="$HOME/.local/bin/claude"

# Aliases — Docker
alias d='docker'
alias dc='docker compose'
alias dcup='docker compose up'
alias dsp='docker system prune --all --force'
alias docker_rmi_dangling='docker rmi $(docker images -qa -f "dangling=true") -f'

# Aliases — python
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

# Aliases — git
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

# Aliases — kube
alias ku='kubectl'
alias kuc='kubectl config'

# Aliases — dbt
alias docs="dbt docs generate; dbt docs serve"
alias dbtb="dbt build"
alias dbtc="dbt compile"
alias dbtr="dbt run"

# Aliases — rust
alias cb="cargo build"
alias cr="cargo run"
alias ct="cargo test"

# Aliases — modal
alias md="modal deploy"
alias mr="modal run"

# Aliases — terraform
alias tf="terraform"

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
# (OMZ git plugin removed — it loads after the custom git aliases above and was
# shadowing them, e.g. its gl='git pull' clobbered gl='git log --reverse -n 10')
plugins=()

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
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" --no-use  # Load nvm without auto-use (auto-use errors with "N/A" when no .nvmrc is set)
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
alias snowsql=/Applications/SnowSQL.app/Contents/MacOS/snowsql

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

# Load the Google Cloud SDK installed by assimilate.sh, or an existing SDK.
_gcloud_sdk_root="$HOME/.local/share/google-cloud-sdk"
if [ ! -d "$_gcloud_sdk_root" ] && (( $+commands[gcloud] )); then
  _gcloud_sdk_root="${commands[gcloud]:A:h:h}"
elif [ ! -d "$_gcloud_sdk_root" ] && [ -d "$HOME/work/dev/google-cloud-sdk" ]; then
  _gcloud_sdk_root="$HOME/work/dev/google-cloud-sdk"
fi
[ -f "$_gcloud_sdk_root/path.zsh.inc" ] && source "$_gcloud_sdk_root/path.zsh.inc"
[ -f "$_gcloud_sdk_root/completion.zsh.inc" ] && source "$_gcloud_sdk_root/completion.zsh.inc"
unset _gcloud_sdk_root
