#!/usr/bin/env sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
managed_config="$script_dir/config.managed.toml"
codex_home=${CODEX_HOME:-"$HOME/.codex"}
dest_config="$codex_home/config.toml"
backup_config="$codex_home/config.toml.dotfiles-backup"

if ! command -v yq >/dev/null 2>&1; then
  echo "error: yq is required to sync Codex settings" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "error: codex is required to validate Codex settings" >&2
  exit 1
fi

mkdir -p "$codex_home"
tmp_config=$(mktemp "$codex_home/.config.toml.XXXXXX")
validation_home=$(mktemp -d "${TMPDIR:-/tmp}/codex-config-validation.XXXXXX")

cleanup() {
  rm -f "$tmp_config"
  rm -rf "$validation_home"
}
trap cleanup EXIT HUP INT TERM

if [ -f "$dest_config" ]; then
  yq eval-all \
    --input-format=toml \
    --output-format=toml \
    'select(fileIndex == 0) * select(fileIndex == 1)' \
    "$dest_config" "$managed_config" > "$tmp_config"
else
  cp "$managed_config" "$tmp_config"
fi

chmod 600 "$tmp_config"
cp "$tmp_config" "$validation_home/config.toml"
validation_log="$validation_home/stderr.log"
if ! CODEX_HOME="$validation_home" \
  codex app-server --strict-config --listen stdio:// \
    </dev/null >/dev/null 2>"$validation_log"; then
  cat "$validation_log" >&2
  exit 1
fi

if [ -f "$dest_config" ] && [ ! -f "$backup_config" ]; then
  cp -p "$dest_config" "$backup_config"
  chmod 600 "$backup_config"
fi

mv "$tmp_config" "$dest_config"
tmp_config=

echo "> Synced managed Codex settings to $dest_config"
