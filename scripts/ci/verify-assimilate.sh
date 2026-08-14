#!/usr/bin/env bash

set -euxo pipefail

: "${DOTFILES:?DOTFILES must point to the checked-out repository}"
export PATH="$HOME/.local/bin:$PATH"

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

test "$(HOME="$HOME" bash --noprofile -ic 'printf %s "$UV_MALWARE_CHECK"' 2>/dev/null)" = 1
test "$(HOME="$HOME" zsh -c 'source "$HOME/.zshrc" >/dev/null 2>&1; printf %s "$UV_MALWARE_CHECK"')" = 1
test "$("$HOME/.local/bin/delta" --version)" = "delta 0.19.2"
test -x "$HOME/.cargo/bin/rustc"
test -d "$HOME/.oh-my-zsh/.git"
test -d "$HOME/.tmux/plugins/tpm/.git"
test -d "$HOME/.tmux/plugins/tmux-powerline/.git"
test -d "$HOME/.local/share/nvim/site/pack/packer/start/packer.nvim/.git"

nvim_log="$(mktemp)"
if ! HOME="$HOME" nvim --headless -c 'quitall' >"$nvim_log" 2>&1; then
  cat "$nvim_log" >&2
  rm -f "$nvim_log"
  exit 1
fi
if grep -Fq 'Error detected while processing' "$nvim_log"; then
  cat "$nvim_log" >&2
  rm -f "$nvim_log"
  exit 1
fi
rm -f "$nvim_log"

git -C "$DOTFILES" diff --exit-code
git -C "$DOTFILES" diff --cached --exit-code
