#!/usr/bin/env sh

set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$test_dir/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/codex-sync.XXXXXX")
codex_home="$test_root/codex-home"
invalid_home="$test_root/invalid-home"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$codex_home" "$invalid_home"
cp "$test_dir/fixtures/codex/config.toml" "$codex_home/config.toml"
cp "$test_dir/fixtures/codex/invalid-config.toml" "$invalid_home/config.toml"

original_hash=$(shasum -a 256 "$codex_home/config.toml" | awk '{print $1}')
CODEX_HOME="$codex_home" "$repo_root/codex/sync-config.sh"

config="$codex_home/config.toml"
backup="$codex_home/config.toml.dotfiles-backup"

assert_value() {
  expression=$1
  expected=$2
  actual=$(yq --input-format=toml --output-format=yaml --unwrapScalar "$expression" "$config")
  if [ "$actual" != "$expected" ]; then
    echo "expected $expression to be $expected, got $actual" >&2
    exit 1
  fi
}

assert_value '.model' 'keep-me'
assert_value '.model_verbosity' 'low'
assert_value '.model_reasoning_summary' 'concise'
assert_value '.personality' 'pragmatic'
assert_value '.approvals_reviewer' 'auto_review'
assert_value '.project_doc_fallback_filenames[0]' 'CLAUDE.md'
assert_value '.project_doc_max_bytes' '196608'
assert_value '.notify[0]' '/bin/sh'
assert_value '.desktop."git-branch-prefix"' 'local/'
assert_value '.projects."/tmp/example".trust_level' 'trusted'
assert_value '.mcp_servers.local.command' 'true'

test "$(stat -f '%Lp' "$config")" = "600"
test -f "$backup"
test "$(shasum -a 256 "$backup" | awk '{print $1}')" = "$original_hash"

first_hash=$(shasum -a 256 "$config" | awk '{print $1}')
CODEX_HOME="$codex_home" "$repo_root/codex/sync-config.sh"
second_hash=$(shasum -a 256 "$config" | awk '{print $1}')
test "$first_hash" = "$second_hash"
test "$(shasum -a 256 "$backup" | awk '{print $1}')" = "$original_hash"

invalid_hash=$(shasum -a 256 "$invalid_home/config.toml" | awk '{print $1}')
set +e
CODEX_HOME="$invalid_home" "$repo_root/codex/sync-config.sh" >/dev/null 2>&1
status=$?
set -e
test "$status" -ne 0
test "$(shasum -a 256 "$invalid_home/config.toml" | awk '{print $1}')" = "$invalid_hash"

echo "Codex config sync preserves local settings and applies managed values"
