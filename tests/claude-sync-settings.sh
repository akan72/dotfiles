#!/usr/bin/env sh

set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$test_dir/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/claude-sync.XXXXXX")
claude_home="$test_root/claude-home"
invalid_home="$test_root/invalid-home"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$claude_home" "$invalid_home"
cp "$test_dir/fixtures/claude/settings.json" "$claude_home/settings.json"
cp "$test_dir/fixtures/claude/invalid-settings.json" "$invalid_home/settings.json"

original_hash=$(shasum -a 256 "$claude_home/settings.json" | awk '{print $1}')
CLAUDE_CONFIG_DIR="$claude_home" "$repo_root/claude/sync-settings.sh"

settings="$claude_home/settings.json"
backup="$claude_home/settings.json.dotfiles-backup"
managed="$repo_root/claude/settings.managed.json"

test "$(jq -r '.attribution.commit' "$settings")" = ""
test "$(jq -r '.attribution.pr' "$settings")" = ""
test "$(jq -r '.attribution.sessionUrl' "$settings")" = "false"
test "$(jq -r '.outputStyle' "$settings")" = "Concise"
test "$(jq -r '.statusLine.type' "$settings")" = "command"
test "$(jq -r '.statusLine.command' "$settings")" = "~/.claude/statusline.sh"
test "$(jq -r '.statusLine.padding' "$settings")" = "0"
test "$(jq -r '.model' "$settings")" = "keep-me"
test "$(jq -r '.enabledPlugins.local' "$settings")" = "true"
test "$(jq -r 'has("permissions")' "$managed")" = "false"
test "$(jq -r 'has("hooks")' "$managed")" = "false"
test "$(jq -r 'has("enabledPlugins")' "$managed")" = "false"
test "$(stat -f '%Lp' "$settings")" = "600"
test -f "$backup"
test "$(shasum -a 256 "$backup" | awk '{print $1}')" = "$original_hash"

first_hash=$(shasum -a 256 "$settings" | awk '{print $1}')
CLAUDE_CONFIG_DIR="$claude_home" "$repo_root/claude/sync-settings.sh"
second_hash=$(shasum -a 256 "$settings" | awk '{print $1}')
test "$first_hash" = "$second_hash"
test "$(shasum -a 256 "$backup" | awk '{print $1}')" = "$original_hash"

invalid_hash=$(shasum -a 256 "$invalid_home/settings.json" | awk '{print $1}')
set +e
CLAUDE_CONFIG_DIR="$invalid_home" "$repo_root/claude/sync-settings.sh" >/dev/null 2>&1
status=$?
set -e
test "$status" -ne 0
test "$(shasum -a 256 "$invalid_home/settings.json" | awk '{print $1}')" = "$invalid_hash"

echo "Claude settings sync applies portable defaults and preserves local settings"
