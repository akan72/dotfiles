#!/usr/bin/env sh

set -ex

PREFIX="$HOME"
DOTFILES="$PREFIX/dotfiles"
BACKUPS="$PREFIX/backups"

function sym () {
  src="$DOTFILES/$1"
  dest="$PREFIX/$2"

  # Save existing dotfiles
  if [ -e "$dest" ]; then
    newdest="$BACKUPS/$(basename $dest)-$(date +%s)"
    mv "$dest" "$newdest"
    echo "> Moved $dest to $newdest"
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
sym vimrc               .vimrc
sym nvim                .config/nvim
sym hammerspoon         .hammerspoon
sym code_settings.json  .vscode/settings.json

echo "> Assimilation successful!"

