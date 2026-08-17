#!/usr/bin/env sh

set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$test_dir/.." && pwd)
test_home=$(mktemp -d "${TMPDIR:-/tmp}/assimilate-path.XXXXXX")
codex_marker="$test_home/codex-called"

cleanup() {
  rm -rf "$test_home"
}
trap cleanup EXIT HUP INT TERM

set +e
HOME="$test_home" \
  PATH="$test_dir/fixtures/bin:$PATH" \
  TEST_CODEX_MARKER="$codex_marker" \
  sh "$repo_root/assimilate.sh" >/dev/null 2>&1
status=$?
set -e

if [ "$status" -ne 1 ]; then
  echo "expected assimilate.sh to reach the stubbed codex command, got status $status" >&2
  exit 1
fi

if [ ! -f "$codex_marker" ]; then
  echo "expected the checkout's Codex sync script to invoke codex" >&2
  exit 1
fi

expected_args='app-server --strict-config --listen stdio://'
actual_args=$(sed -n '1p' "$codex_marker")
if [ "$actual_args" != "$expected_args" ]; then
  echo "expected Codex validator arguments $expected_args, got $actual_args" >&2
  exit 1
fi

echo "assimilate.sh resolves files relative to its own checkout"
