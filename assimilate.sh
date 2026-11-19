#!/usr/bin/env bash
set -Eeuo pipefail

OS="$(uname -s)"
ARCH="$(uname -m)"
PREFIX="$HOME"
DOTFILES=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=scripts/security/pins.sh disable=SC1091 # Checked as its own input.
source "$DOTFILES/scripts/security/pins.sh"
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
  case "$url" in
    https://*|/*) ;; # Reviewed public HTTPS origins, or local test fixtures.
    *) echo 'only reviewed HTTPS origins are supported' >&2; return 1 ;;
  esac
  if [ "$preflight" = 1 ]; then return 0; fi
  # Pinned repositories are public: fetch anonymously, ignoring this machine's
  # Git config, so no credential helper, URL rewrite or prompt is ever used.
  env -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_TERMINAL_PROMPT=0 GIT_ASKPASS='' SSH_ASKPASS='' \
    git -c credential.helper= -c core.fsmonitor=false -c core.hooksPath=/dev/null -c fetch.recurseSubmodules=false \
    -C "$dir" fetch --depth 1 origin "$sha"
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
  local action="$1" entries name commit origin
  command -v jq >/dev/null || { echo 'jq is required to read the plugin lock' >&2; return 1; }
  # Every locked plugin needs a reviewed origin in plugin-origins.json; null
  # marks a disabled plugin that is never installed or loaded.
  entries=$(jq -er --slurpfile origins "$DOTFILES/nvim/plugin-origins.json" '
    to_entries[] | .key as $name
    | if ($origins[0] | has($name)) | not then error("unreviewed plugin in lock: \($name)") else . end
    | select($origins[0][$name] != null) | [$name, .value.commit, $origins[0][$name]] | @tsv
  ' "$DOTFILES/nvim/lazy-lock.json") || return 1
  while IFS=$'\t' read -r name commit origin; do
    "$action" "https://github.com/$origin.git" "$HOME/.local/share/nvim/lazy/$name" "$commit" --allow-help-tags
  done <<< "$entries"
}

function checkout_preflight () {
  check_existing "$OMZ_ORIGIN" "$HOME/.oh-my-zsh" "$OMZ_COMMIT"
  check_existing "$AUTOSUGGEST_ORIGIN" "$HOME/.local/share/zsh-plugins/zsh-autosuggestions" "$AUTOSUGGEST_COMMIT"
  check_existing "$HIGHLIGHT_ORIGIN" "$HOME/.local/share/zsh-plugins/zsh-syntax-highlighting" "$HIGHLIGHT_COMMIT"
  check_existing "$POWERLINE_ORIGIN" "$HOME/.tmux/plugins/tmux-powerline" "$POWERLINE_COMMIT" --allow-userinfo
  if [ -d "$HOME/.local/share/nvim/lazy" ]; then nvim_checkouts check_existing; fi
}

# The reviewed CLI artifacts this platform needs, one TOOL:VERSION per line.
function cli_artifacts () {
  [ -x "$HOME/.cargo/bin/rustup" ] || echo rustup-init:1.29.2
  case "$OS-$ARCH" in Darwin-arm64|Linux-x86_64) echo delta:0.19.2 ;; esac
  echo gcloud:577.0.0
  [ "$OS-$ARCH" != Linux-x86_64 ] || echo nvim:0.12.4
  # Pinned Node and CLI tools; assimilate itself needs jq and yq from here.
  case "$OS-$ARCH" in Darwin-arm64|Darwin-x86_64|Linux-x86_64|Linux-aarch64)
    echo ca-bundle:2026-11-05 node:26.13.1 lsd:1.2.0 yq:4.54.3 jq:1.8.2 gh:2.103.3 terraform:1.17.1 duckdb:2.0.0 ;;
  esac
  case "$OS" in Darwin) echo nvim:0.12.6 hack-nerd-font:3.5.1 ;; esac
}

function cli_preflight () {
  local request failed=0
  # Check every tool before failing, so one run reports all conflicts.
  for request in $(cli_artifacts); do
    "$DOTFILES/scripts/security/install-artifact.sh" --check "${request%%:*}" "${request#*:}" "$OS-$ARCH" || failed=1
  done
  [ "$failed" = 0 ]
}

function installation_preflight () {
  cli_preflight
  source_preflight
  fonts_preflight
  precommit_preflight
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
# Keep both Bun discovery modes: absolute XDG takes precedence over HOME.
sym .bunfig.toml                    .bunfig.toml
sym .bunfig.toml                    .config/.bunfig.toml
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
}

# On macOS, tmux, mosh and PostgreSQL are built from reviewed source
# (scripts/security/sources.json) and linked into ~/.local/bin; links replace only
# symlinks, never real files. Linux hosts use their distribution's signed packages.
function source_tools () {
  local name version tool link
  if [ "$OS" != Darwin ]; then notice 'SKIP source builds: use the distribution packages for tmux, mosh and PostgreSQL'; return 0; fi
  for name in tmux mosh postgresql; do
    "$DOTFILES/scripts/security/build-source.sh" "$name"
    version=$(jq -er --arg n "$name" '.sources[$n].version' "$DOTFILES/scripts/security/sources.json")
    for tool in "$HOME/.local/share/dotfiles-src/$name-$version"/bin/*; do
      link="$HOME/.local/bin/${tool##*/}"
      if [ -L "$link" ] && [ "$(readlink "$link")" = "$tool" ]; then continue; fi
      [ ! -e "$link" ] || [ -L "$link" ] || { echo "Review existing $link" >&2; return 1; }
      ln -sfn "$tool" "$link"
    done
  done
}

function source_preflight () {
  local name failed=0
  [ "$OS" = Darwin ] || return 0
  for name in tmux mosh postgresql; do
    "$DOTFILES/scripts/security/build-source.sh" --check "$name" || failed=1
  done
  [ "$failed" = 0 ]
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

# An installed pre-commit venv must still match the lock it was built from.
function precommit_preflight () {
  local venv="$HOME/.local/share/dotfiles-pre-commit"
  [ -e "$venv" ] || return 0
  python3 -I "$DOTFILES/scripts/security/verify-venv.py" "$venv" "$venv/requirements.txt"
}

function python_and_hooks () {
if command -v uv >/dev/null 2>&1; then
  uv python install
fi

# pre-commit comes from a hash-locked lock in its own venv, not Homebrew.
local lock="$DOTFILES/scripts/security/requirements-pre-commit-py312.txt" venv="$HOME/.local/share/dotfiles-pre-commit"
if command -v uv >/dev/null 2>&1 && ! cmp -s "$lock" "$venv/requirements.txt"; then
  command uv venv --clear --python 3.12 "$venv"
  command uv pip install --python "$venv/bin/python" --require-hashes --only-binary :all: --no-deps -r "$lock"
  cp "$lock" "$venv/requirements.txt"
fi
[ ! -e "$venv" ] || python3 -I "$DOTFILES/scripts/security/verify-venv.py" "$venv" "$lock"
if [ -x "$venv/bin/pre-commit" ]; then
  [ ! -e "$HOME/.local/bin/pre-commit" ] || [ -L "$HOME/.local/bin/pre-commit" ] || { echo "Review existing $HOME/.local/bin/pre-commit" >&2; return 1; }
  ln -sfn "$venv/bin/pre-commit" "$HOME/.local/bin/pre-commit"
fi

# Install repository security hooks.
if command -v pre-commit >/dev/null 2>&1 && [ "${ASSIMILATE_SOURCE_MODE:-git}" = git ]; then
  (cd "$DOTFILES" && pre-commit install --allow-missing-config)
fi

}

function omz_checkout () {
clone_pinned "$OMZ_ORIGIN" "$HOME/.oh-my-zsh" "$OMZ_COMMIT"
clone_pinned "$AUTOSUGGEST_ORIGIN" "$HOME/.local/share/zsh-plugins/zsh-autosuggestions" "$AUTOSUGGEST_COMMIT"
clone_pinned "$HIGHLIGHT_ORIGIN" "$HOME/.local/share/zsh-plugins/zsh-syntax-highlighting" "$HIGHLIGHT_COMMIT"
}

function install_clis () {
local request
if [ -x "$HOME/.cargo/bin/rustup" ]; then
  notice 'Rustup: already installed; keeping your Rust toolchains (reviewed version: 1.29.2).'
fi
case "$OS-$ARCH" in
  Darwin-arm64|Linux-x86_64) ;;
  Darwin-x86_64) echo 'No reviewed delta artifact for Intel Macs.' ;;
  *) echo "No reviewed delta artifact for $OS-$ARCH" >&2 ;;
esac
for request in $(cli_artifacts); do
  DOTFILES_ARTIFACT_PROGRESS_FD=3 "$DOTFILES/scripts/security/install-artifact.sh" "${request%%:*}" "${request#*:}" "$OS-$ARCH"
done
link_node
link_fonts
# The Linux Neovim artifact links into ~/.local/bin, used by the plugin step.
export PATH="$HOME/.local/bin:$PATH"
}

# Point ~/.local/bin/node, npm and npx at the pinned Node; replace only symlinks
# (such as an old nvm link), never a regular file someone installed there.
# macOS only reads fonts from ~/Library/Fonts: copy the pinned Hack Nerd Font there.
# Copies must stay byte-identical to the verified pinned files; any other file
# with the same name is refused, never overwritten. --check runs the same test.
function fonts_preflight () {
  local source="$HOME/.local/share/fonts/hack-nerd-font-3.5.1" font dest failed=0
  [ "$OS" = Darwin ] && [ -d "$source" ] || return 0
  for font in "$source"/*.ttf; do
    dest="$HOME/Library/Fonts/${font##*/}"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      if [ -L "$dest" ] || ! cmp -s "$font" "$dest"; then
        echo "Review existing $dest: it is not the pinned Hack Nerd Font" >&2; failed=1
      fi
    fi
  done
  [ "$failed" = 0 ]
}

function link_fonts () {
  local source="$HOME/.local/share/fonts/hack-nerd-font-3.5.1" font dest
  [ "$OS" = Darwin ] && [ -d "$source" ] || return 0
  fonts_preflight
  mkdir -p "$HOME/Library/Fonts"
  for font in "$source"/*.ttf; do
    dest="$HOME/Library/Fonts/${font##*/}"
    [ -e "$dest" ] || cp "$font" "$dest"
  done
}

function link_node () {
  local root="$HOME/.local/share/dotfiles-node/v26.13.1" tool link
  [ -x "$root/bin/node" ] || { notice 'SKIP Node links: no reviewed Node for this platform'; return 0; }
  mkdir -p "$HOME/.local/bin"
  for tool in node npm npx; do
    link="$HOME/.local/bin/$tool"
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$root/bin/$tool" ]; then continue; fi
    [ ! -e "$link" ] || [ -L "$link" ] || { echo "Review existing $link" >&2; return 1; }
    ln -sfn "$root/bin/$tool" "$link"
  done
}

function tmux_checkouts () {
clone_pinned "$POWERLINE_ORIGIN" "$HOME/.tmux/plugins/tmux-powerline" "$POWERLINE_COMMIT" --allow-userinfo
}

function nvim_plugins () {
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
TOTAL_STEPS=10
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
run_step 'Package policy' package_policy
run_step 'Verified CLI artifacts' install_clis
run_step 'Agent settings' sync_agents
run_step 'Python and Git hooks' python_and_hooks
run_step 'Oh My Zsh and zsh plugin checkouts' omz_checkout
run_step 'Source builds (tmux, mosh, PostgreSQL)' source_tools
run_step 'tmux checkouts' tmux_checkouts
run_step 'Neovim checkouts' nvim_plugins
printf '\nAssimilation Successful!\nLogs: %s\n' "$LOG_DIR"
