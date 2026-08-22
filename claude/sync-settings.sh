#!/usr/bin/env sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
managed_settings="$script_dir/settings.managed.json"
claude_home=${CLAUDE_CONFIG_DIR:-"$HOME/.claude"}
dest_settings="$claude_home/settings.json"
backup_settings="$claude_home/settings.json.dotfiles-backup"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required to sync Claude settings" >&2
  exit 1
fi

mkdir -p "$claude_home"
tmp_settings=$(mktemp "$claude_home/.settings.json.XXXXXX")

cleanup() {
  rm -f "$tmp_settings"
}
trap cleanup EXIT HUP INT TERM

if [ -f "$dest_settings" ]; then
  jq -s '.[0] * .[1]' "$dest_settings" "$managed_settings" > "$tmp_settings"
else
  jq '.' "$managed_settings" > "$tmp_settings"
fi

jq -e 'type == "object"' "$tmp_settings" >/dev/null
chmod 600 "$tmp_settings"

if [ -f "$dest_settings" ] && [ ! -f "$backup_settings" ]; then
  cp -p "$dest_settings" "$backup_settings"
  chmod 600 "$backup_settings"
fi

mv "$tmp_settings" "$dest_settings"
tmp_settings=

echo "> Synced managed Claude settings to $dest_settings"
