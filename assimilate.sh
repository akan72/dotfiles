#!/usr/bin/env bash
set -Eeuo pipefail

OS="$(uname -s)"
ARCH="$(uname -m)"
PREFIX="$HOME"
DOTFILES=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
BACKUPS="$PREFIX/backups"
VERBOSE=0
CHECK_ONLY=0
for argument in "$@"; do
  case "$argument" in
    --verbose) VERBOSE=1 ;;
    --check) CHECK_ONLY=1 ;;
    --help) printf 'usage: bash assimilate.sh [--check] [--verbose]\n--check validates existing checkouts and CLI installations without configuring or installing; writes private logs only.\n'; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$argument" >&2; exit 2 ;;
  esac
done

function notice () {
  printf '  %s\n' "$*" >&3
}

function report_failure () {
  local status="$1"
  trap - ERR
  printf '  FAILED: %s (exit %s)\n' "$STEP_NAME" "$status" >&4
  if [ -s "$STEP_LOG" ]; then
    if [ "$VERBOSE" = 1 ]; then cat "$STEP_LOG" >&4
    else tail -n 30 "$STEP_LOG" >&4; fi
  fi
  printf '  Full log: %s\n' "$STEP_LOG" >&4
  exit "$status"
}

function run_step () {
  STEP_NAME="$1"
  shift
  STEP_NUMBER=$((STEP_NUMBER + 1))
  STEP_LOG="$LOG_DIR/$(printf '%02d' "$STEP_NUMBER").log"
  printf '[%02d/%02d] %s\n' "$STEP_NUMBER" "$TOTAL_STEPS" "$STEP_NAME" >&3
  "$@" >"$STEP_LOG" 2>&1
  if [ "$VERBOSE" = 1 ] && [ -s "$STEP_LOG" ]; then cat "$STEP_LOG" >&3; fi
  printf '  OK\n' >&3
}

function sym () {
  src="$DOTFILES/$1"
  dest="$PREFIX/$2"

  # Ensure parent directory exists
  mkdir -p "$(dirname "$dest")"

  # An already-correct link is installed. Leaving it alone makes repeated
  # assimilation safe and avoids filling the backup directory on every run.
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    return
  fi

  # Save existing dotfiles (also matches dangling symlinks, where -e alone returns false)
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    backup="$(mktemp -d "$BACKUPS/$(basename "$dest").XXXXXX")"
    rmdir "$backup"
    mv "$dest" "$backup"
    echo "> Moved $dest to $backup"
  fi

  # Symlink new dotfiles
  ln -s "$src" "$dest"
}

function clone_pinned () {
  local url="$1" dir="$2" sha="$3" helper="$DOTFILES/scripts/security/check-clone.sh"
  local preflight=0
  case "${5:-}" in --preflight) preflight=1 ;; '') ;; *) return 2 ;; esac
  local args=("$dir" "$url" "$sha")
  case "${4:-}" in
    --allow-help-tags) args=(--allow-help-tags "${args[@]}") ;;
    --allow-userinfo) args=(--allow-userinfo "${args[@]}") ;;
    '') ;;
    *) echo 'unsupported checkout policy flag' >&2; return 1 ;;
  esac
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'full commit SHA required' >&2; return 1; }
  if [ -e "$dir" ] || [ -L "$dir" ]; then
    "$helper" --clean "${args[@]}" || return 1
    if "$helper" "${args[@]}" >/dev/null 2>&1; then return; fi
  else
    mkdir -p "$(dirname "$dir")"
    git -c core.hooksPath=/dev/null init -q "$dir"
    git -c core.hooksPath=/dev/null -C "$dir" remote add origin "$url"
  fi
  # Observe routing only; never ask a credential helper to return a secret.
  case "$url" in
    https://*)
      local selected_helper selected_user remote_url
      remote_url=$(git -c core.fsmonitor=false -C "$dir" remote get-url origin)
      selected_helper=$(git config --get-urlmatch credential.helper "$remote_url") || true
      selected_user=$(git config --get-urlmatch credential.username "$remote_url") || true
      if [ -z "$selected_helper" ] || [ -z "$selected_user" ]; then
        echo "Git routing missing for $url; configure the expected helper and username before bootstrap" >&2
        return 1
      fi
      printf 'Git routing verified for reviewed origin\n'
      ;;
    /*) ;; # Local fixture repositories require no credential routing.
    *) echo 'only reviewed HTTPS origins are supported' >&2; return 1 ;;
  esac
  if [ "$preflight" = 1 ]; then return 0; fi
  git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c fetch.recurseSubmodules=false -C "$dir" fetch --depth 1 origin "$sha"
  git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c submodule.recurse=false -C "$dir" checkout -q --detach "$sha"
  "$helper" "${args[@]}"
}

function check_existing () {
  local url="$1" dir="$2" sha="$3"
  if [ -e "$dir" ] || [ -L "$dir" ]; then
    clone_pinned "$url" "$dir" "$sha" "${4:-}" --preflight
  fi
}

function nvim_checkouts () {
  local action="$1" plugin_entries name commit origin
  command -v jq >/dev/null || { echo 'jq is required to read the plugin lock' >&2; exit 1; }
  plugin_entries=$(jq -er 'to_entries[] | [.key, .value.commit] | @tsv' "$DOTFILES/nvim/lazy-lock.json")
  while IFS=$'\t' read -r name commit; do
    case "$name" in
      Comment.nvim) origin=numToStr/Comment.nvim ;;
      bufferline.nvim) origin=akinsho/bufferline.nvim ;;
      gruvbox.nvim) origin=ellisonleao/gruvbox.nvim ;;
      indent-blankline.nvim) origin=lukas-reineke/indent-blankline.nvim ;;
      lazy.nvim) origin=folke/lazy.nvim ;;
      lualine.nvim) origin=nvim-lualine/lualine.nvim ;;
      markdown-preview.nvim) continue ;; # Disabled until release artifacts are reviewed.
      nvim-lspconfig) origin=neovim/nvim-lspconfig ;;
      nvim-tree.lua) origin=nvim-tree/nvim-tree.lua ;;
      nvim-treesitter) origin=nvim-treesitter/nvim-treesitter ;;
      nvim-web-devicons) origin=nvim-tree/nvim-web-devicons ;;
      plenary.nvim) origin=nvim-lua/plenary.nvim ;;
      telescope.nvim) origin=nvim-telescope/telescope.nvim ;;
      vim-fugitive) origin=tpope/vim-fugitive ;;
      vim-gitgutter) origin=airblade/vim-gitgutter ;;
      *) echo "unreviewed plugin in lock: $name" >&2; exit 1 ;;
    esac
    "$action" "https://github.com/$origin.git" "$HOME/.local/share/nvim/lazy/$name" "$commit" --allow-help-tags
  done <<< "$plugin_entries"
}

function checkout_preflight () {
  check_existing https://github.com/ohmyzsh/ohmyzsh "$HOME/.oh-my-zsh" e7aa0c56e68348afefdd6af4c5bdb314a2bd6640
  check_existing https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" 7bdb7ca33c9cc6440a600202b50142f401b6fe21
  check_existing https://github.com/erikw/tmux-powerline "$HOME/.tmux/plugins/tmux-powerline" 6079ace8d534a01d4d964b8b854b223f72edaf4b --allow-userinfo
  if [ -d "$HOME/.local/share/nvim/lazy" ]; then nvim_checkouts check_existing; fi
}

function cli_preflight () {
  local installer="$DOTFILES/scripts/security/install-artifact.sh"
  local requests=(gcloud:577.0.0) request tool version failed=0
  if [ ! -x "$HOME/.cargo/bin/rustup" ]; then requests+=(rustup-init:1.29.2); fi
  case "$OS-$ARCH" in
    Darwin-arm64|Linux-x86_64) requests+=(delta:0.19.2) ;;
  esac
  if [ "$OS-$ARCH" = Linux-x86_64 ]; then requests+=(nvim:0.12.4); fi
  # Collect all CLI conflicts so one run reports both delta and gcloud.
  for request in "${requests[@]}"; do
    tool="${request%%:*}" version="${request#*:}"
    if ! "$installer" --check "$tool" "$version" "$OS-$ARCH"; then failed=1; fi
  done
  [ "$failed" = 0 ]
}

function installation_preflight () {
  cli_preflight
  checkout_preflight
}

function link_config () {
mkdir -p "$BACKUPS/vim_backups"

# Shared symlinks (work on macOS and Linux)
sym bash_profile        .bash_profile
sym shared.sh           .shared.sh
sym gitconfig           .gitconfig
sym tmux.conf           .tmux.conf
sym zshrc               .zshrc
sym nvim                .config/nvim
sym tmux-powerline/config.sh        .config/tmux-powerline/config.sh
sym tmux-powerline/themes/theme.sh  .config/tmux-powerline/themes/theme.sh
sym claude/statusline.sh            .claude/statusline.sh
sym agent-instructions.md           .claude/CLAUDE.md
sym agent-instructions.md           .codex/AGENTS.md
sym ssh/config                      .ssh/config
sym uv/uv.toml                      .config/uv/uv.toml
# Bun reads this explicit user configuration; application state stays outside the repo.
sym .bunfig.toml                    .bunfig.toml
sym ghostty/config                 .config/ghostty/config

# Lock down sensitive symlink targets (chmod follows the symlink to the repo file).
chmod 600 "$HOME/.gitconfig"
chmod 700 "$HOME/.ssh"
chmod 600 "$HOME/.ssh/config"

# bashrc: symlinked on macOS; sourced from a stub on Linux.
# On the EC2 dev box, user_data appends a secrets/region block to .bashrc after
# this script runs. If .bashrc were a symlink into the repo, those appends would
# write into the dotfiles repo's tracked file. So on Linux, leave .bashrc as a
# regular file and source the dotfiles bashrc from it.
if [ "$OS" = "Darwin" ]; then
  sym bashrc .bashrc
else
  if ! grep -Fq 'dotfiles/bashrc' "$PREFIX/.bashrc" 2>/dev/null; then
    # shellcheck disable=SC2016 # HOME expands in the future login shell.
    echo '[ -f "$HOME/dotfiles/bashrc" ] && . "$HOME/dotfiles/bashrc"' >> "$PREFIX/.bashrc"
  fi
fi

if [ "$OS" = Darwin ]; then
  sym hammerspoon                 .hammerspoon
  sym vscode/code_settings.json   .vscode/settings.json
  sym zed/settings.json           .config/zed/settings.json
  sym zed/keymap.json             .config/zed/keymap.json
  sym ghostty/config              Library/Application\ Support/com.mitchellh.ghostty/config

fi
}

function package_policy () {
"$DOTFILES/scripts/security/npm-age.sh"
if [ "$OS" = Darwin ]; then
  if ! HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ANALYTICS=1 \
    brew bundle check --quiet --no-upgrade --file="$DOTFILES/Brewfile"; then
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ANALYTICS=1 \
      brew bundle install --no-upgrade --file="$DOTFILES/Brewfile"
  fi
else
  notice 'SKIP Homebrew on this platform'
fi
}

function sync_agents () {
if command -v jq >/dev/null 2>&1; then
  "$DOTFILES/claude/sync-settings.sh"
else
  notice "SKIP Claude settings: jq is unavailable"
fi
if command -v yq >/dev/null 2>&1 && command -v codex >/dev/null 2>&1; then
  "$DOTFILES/codex/sync-config.sh"
else
  notice "SKIP Codex settings: yq or codex is unavailable"
fi

}

function python_and_hooks () {
if command -v uv >/dev/null 2>&1; then
  uv python install
fi

# Install repository security hooks when pre-commit is available (Homebrew
# supplies it on macOS). Linux users can install pre-commit independently.
if command -v pre-commit >/dev/null 2>&1 && [ "${ASSIMILATE_SOURCE_MODE:-git}" = git ]; then
  (cd "$DOTFILES" && pre-commit install --allow-missing-config)
fi

}

function omz_checkout () {
clone_pinned https://github.com/ohmyzsh/ohmyzsh "$HOME/.oh-my-zsh" e7aa0c56e68348afefdd6af4c5bdb314a2bd6640
}

function install_clis () {
ARTIFACT_INSTALL="$DOTFILES/scripts/security/install-artifact.sh"
if [ ! -x "$HOME/.cargo/bin/rustup" ]; then
  DOTFILES_ARTIFACT_PROGRESS_FD=3 "$ARTIFACT_INSTALL" rustup-init 1.29.2 "$OS-$ARCH"
else
  notice 'Rustup: already installed; skipping installation and keeping your Rust toolchains.'
  notice 'Check your version with: rustup --version (reviewed version: 1.29.2).'
fi
case "$OS-$ARCH" in
  Darwin-arm64|Linux-x86_64) DOTFILES_ARTIFACT_PROGRESS_FD=3 "$ARTIFACT_INSTALL" delta 0.19.2 "$OS-$ARCH" ;;
  Darwin-x86_64) echo 'Intel delta: use the reviewed Homebrew git-delta channel.' ;;
  *) echo "No reviewed delta artifact for $OS-$ARCH" >&2 ;;
esac
DOTFILES_ARTIFACT_PROGRESS_FD=3 "$ARTIFACT_INSTALL" gcloud 577.0.0 "$OS-$ARCH"

}

function tmux_checkouts () {
clone_pinned https://github.com/tmux-plugins/tpm     "$HOME/.tmux/plugins/tpm"            7bdb7ca33c9cc6440a600202b50142f401b6fe21  # v3.1.0
clone_pinned https://github.com/erikw/tmux-powerline "$HOME/.tmux/plugins/tmux-powerline" 6079ace8d534a01d4d964b8b854b223f72edaf4b --allow-userinfo  # v3.2.0

}

function install_nvim () {
if [ "$OS-$ARCH" = Linux-x86_64 ]; then
  DOTFILES_ARTIFACT_PROGRESS_FD=3 "$ARTIFACT_INSTALL" nvim 0.12.4 "$OS-$ARCH"
  export PATH="$HOME/.local/bin:$PATH"
fi
if [ "${ASSIMILATE_SKIP_PLUGIN_SYNC:-0}" != 1 ]; then nvim_checkouts clone_pinned
else notice 'SKIP Neovim checkout sync (explicitly requested)'; fi
}

# Run the reviewed setup phases. Successful child output stays in private logs.
umask 077
LOG_ROOT="$HOME/.local/state/dotfiles-security/assimilate"
for log_parent in "$HOME/.local" "$HOME/.local/state" "$HOME/.local/state/dotfiles-security" "$LOG_ROOT"; do
  [ ! -L "$log_parent" ] || { printf 'Log directory ancestors must not be symlinks\n' >&2; exit 1; }
done
mkdir -p "$LOG_ROOT"
LOG_DIR=$(mktemp -d "$LOG_ROOT/run.XXXXXX")
exec 3>&1 4>&2
STEP_NUMBER=0
TOTAL_STEPS=9
if [ "$CHECK_ONLY" = 1 ]; then TOTAL_STEPS=1; fi
STEP_NAME=Initialization
STEP_LOG="$LOG_DIR/00.log"
trap 'report_failure "$?"' ERR
printf 'Dotfiles setup | %s %s\nLogs: %s\n\n' "$OS" "$ARCH" "$LOG_DIR"
run_step 'Existing installation preflight' installation_preflight
if [ "$CHECK_ONLY" = 1 ]; then
  printf '\nInstallation preflight passed. No configuration or packages changed.\n'
  exit 0
fi
run_step 'Configuration links' link_config
run_step 'Package policy and Homebrew' package_policy
run_step 'Agent settings' sync_agents
run_step 'Python and Git hooks' python_and_hooks
run_step 'Oh My Zsh checkout' omz_checkout
run_step 'Verified CLI artifacts' install_clis
run_step 'tmux checkouts' tmux_checkouts
run_step 'Neovim checkouts' install_nvim
printf '\nAssimilation Successful!\nLogs: %s\n' "$LOG_DIR"
