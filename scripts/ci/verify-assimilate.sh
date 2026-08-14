#!/usr/bin/env bash

set -euo pipefail

: "${DOTFILES:?DOTFILES must point to the checked-out repository}"

assert_link() {
  local source="$DOTFILES/$1"
  local target="$HOME/$2"

  test -L "$target"
  test "$(readlink "$target")" = "$source"
}

assert_link bash_profile .bash_profile
assert_link gitconfig .gitconfig
assert_link tmux.conf .tmux.conf
assert_link zshrc .zshrc
assert_link nvim .config/nvim
assert_link tmux-powerline/config.sh .config/tmux-powerline/config.sh
assert_link tmux-powerline/themes/theme.sh .config/tmux-powerline/themes/theme.sh
assert_link claude/statusline.sh .claude/statusline.sh

if [ "$(uname -s)" = Darwin ]; then
  assert_link bashrc .bashrc
  assert_link hammerspoon .hammerspoon
  assert_link vscode/code_settings.json .vscode/settings.json
  assert_link zed/settings.json .config/zed/settings.json
  assert_link zed/keymap.json .config/zed/keymap.json
  assert_link ghostty/config 'Library/Application Support/com.mitchellh.ghostty/config'
else
  test ! -L "$HOME/.bashrc"
  grep -Fq 'dotfiles/bashrc' "$HOME/.bashrc"
fi

test "$(HOME="$HOME" bash -c 'source "$HOME/.bashrc" >/dev/null 2>&1; printf %s "$UV_MALWARE_CHECK"')" = 1
test "$(HOME="$HOME" zsh -c 'source "$HOME/.zshrc" >/dev/null 2>&1; printf %s "$UV_MALWARE_CHECK"')" = 1
test "$("$HOME/.local/bin/delta" --version)" = "delta 0.19.2"
test -x "$HOME/.cargo/bin/rustc"
test -d "$HOME/.oh-my-zsh/.git"
test -d "$HOME/.tmux/plugins/tpm/.git"
test -d "$HOME/.tmux/plugins/tmux-powerline/.git"

git -C "$DOTFILES" diff --exit-code
git -C "$DOTFILES" diff --cached --exit-code
