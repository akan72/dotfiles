#!/usr/bin/env sh

set -ex

PREFIX="$HOME"
DOTFILES="$PREFIX/dotfiles"
BACKUPS="$PREFIX/backups"

function sym () {
  src="$DOTFILES/$1"
  dest="$PREFIX/$2"

  # Ensure parent directory exists
  mkdir -p "$(dirname "$dest")"

  # Save existing dotfiles (also matches dangling symlinks, where -e alone returns false)
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    backup="$BACKUPS/$(basename $dest)-$(date +%s)"
    mv "$dest" "$backup"
    echo "> Moved $dest to $backup"
  fi

  # Symlink new dotfiles
  ln -s "$src" "$dest"
}

if [ ! -e "$DOTFILES" ]; then
  echo "error: dotfiles/ needs to reside in $PREFIX"
  exit 1
fi

mkdir -p "$BACKUPS/vim_backups"

sym bashrc              .bashrc
sym bash_profile        .bash_profile
sym gitconfig           .gitconfig
sym tmux.conf           .tmux.conf
sym zshrc               .zshrc
sym nvim                .config/nvim
sym hammerspoon         .hammerspoon
sym vscode/code_settings.json  .vscode/settings.json
sym zed/settings.json   .config/zed/settings.json
sym ghostty/config      Library/Application\ Support/com.mitchellh.ghostty/config
sym tmux-powerline/config.sh   .config/tmux-powerline/config.sh
sym tmux-powerline/themes/theme.sh  .config/tmux-powerline/themes/theme.sh
sym claude/statusline.sh .claude/statusline.sh

brew bundle install
echo "> Assimilation successful!"
