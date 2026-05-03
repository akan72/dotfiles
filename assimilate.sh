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

function clone_pinned () {
  url="$1"; dir="$2"; sha="$3"
  if [ ! -d "$dir" ]; then
    git clone --revision="$sha" "$url" "$dir"
  else
    git -C "$dir" checkout "$sha"
  fi
}

# Install oh-my-zsh (clone repo directly; install.sh is just `git clone` once
# its zshrc/runzsh/chsh side-effects are disabled)
clone_pinned https://github.com/ohmyzsh/ohmyzsh "$HOME/.oh-my-zsh" e7aa0c56e68348afefdd6af4c5bdb314a2bd6640  # 2026-04 master HEAD

# Install rust via rustup-init.sh pinned to a specific GitHub commit (immutable),
# with rustc toolchain version locked
if [ ! -d "$HOME/.cargo" ]; then
  RUSTUP_SHA=e10ffbdbb807c47fdd208119de99e7baae3e0dfe  # rustup 1.29.0
  curl --proto '=https' --tlsv1.2 -sSf \
    "https://raw.githubusercontent.com/rust-lang/rustup/$RUSTUP_SHA/rustup-init.sh" \
    | sh -s -- -y --no-modify-path --default-toolchain 1.95.0
fi

# Install git-delta from a pinned GitHub release tarball (sidesteps brew bottle ABI drift)
DELTA_VERSION=0.19.2
DELTA_SHA256=9be36612a5a13e9e386dc498fb8e50dc87c72ee42b63db0ea05b32f99a72a69a
DELTA_BIN="$HOME/.local/bin/delta"
if [ ! -x "$DELTA_BIN" ] || [ "$("$DELTA_BIN" --version 2>/dev/null | awk '{print $2}')" != "$DELTA_VERSION" ]; then
  tmp=$(mktemp -d)
  curl -fsSL "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-aarch64-apple-darwin.tar.gz" -o "$tmp/delta.tar.gz"
  echo "${DELTA_SHA256}  $tmp/delta.tar.gz" | shasum -a 256 -c -
  mkdir -p "$HOME/.local/bin"
  tar -xzf "$tmp/delta.tar.gz" -C "$tmp"
  install -m 755 "$tmp/delta-${DELTA_VERSION}-aarch64-apple-darwin/delta" "$DELTA_BIN"
  rm -rf "$tmp"
fi

# Install tmux plugin manager and plugins declared in tmux.conf
clone_pinned https://github.com/tmux-plugins/tpm     "$HOME/.tmux/plugins/tpm"            7bdb7ca33c9cc6440a600202b50142f401b6fe21  # v3.1.0
clone_pinned https://github.com/erikw/tmux-powerline "$HOME/.tmux/plugins/tmux-powerline" 6079ace8d534a01d4d964b8b854b223f72edaf4b  # v3.2.0

# Install Packer (nvim plugin manager) and run PackerSync
clone_pinned https://github.com/wbthomason/packer.nvim "$HOME/.local/share/nvim/site/pack/packer/start/packer.nvim" ea0cc3c59f67c440c5ff0bbe4fb9420f4350b9a3  # 2023-08-24, matches plugins.lua pin

nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync' || true

echo "> Assimilation successful!"
