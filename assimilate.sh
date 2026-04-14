#!/usr/bin/env sh

set -ex

PREFIX="$HOME"
DOTFILES="$PREFIX/dotfiles"
BACKUPS="$PREFIX/backups"

function sym () {
  src="$DOTFILES/$1"
  dest="$PREFIX/$2"

  # Make dest dir if not exists
  mkdir -p "$dest"?

  # Save existing dotfiles
  if [ -e "$dest" ]; then
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
sym code_settings.json  .vscode/settings.json
sym zed/settings.json   .config/zed/settings.json
sym ghostty/config      Library/Application\ Support/com.mitchellh.ghostty/config

brew bundle install
echo "> Assimilation successful!"
