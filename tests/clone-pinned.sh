#!/usr/bin/env bash

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/clone-pinned.XXXXXX")"

cleanup() {
  rm -rf "$test_root"
}
trap cleanup EXIT HUP INT TERM

# Load only the helper under test without executing the installer.
eval "$(sed -n '/^function clone_pinned () {/,/^}/p' "$repo_root/assimilate.sh")"

source_repo="$test_root/source"
remote_repo="$test_root/remote.git"
install_dir="$test_root/install"

git init --quiet "$source_repo"
git -C "$source_repo" config user.email ci@example.invalid
git -C "$source_repo" config user.name CI
git -C "$source_repo" config commit.gpgsign false
printf 'pinned content\n' > "$source_repo/content"
git -C "$source_repo" add content
git -C "$source_repo" commit --quiet -m fixture
sha="$(git -C "$source_repo" rev-parse HEAD)"

git init --quiet --bare "$remote_repo"
git -C "$source_repo" remote add origin "$remote_repo"
git -C "$source_repo" push --quiet origin HEAD:main

clone_pinned "$remote_repo" "$install_dir" "$sha"
test "$(git -C "$install_dir" rev-parse HEAD)" = "$sha"

# If the second call attempts a fetch, moving the remote makes it fail. A
# successful call therefore proves that an already-pinned checkout is offline.
mv "$remote_repo" "$test_root/remote-offline.git"
clone_pinned "$remote_repo" "$install_dir" "$sha"
test "$(git -C "$install_dir" rev-parse HEAD)" = "$sha"

echo "clone_pinned skips network access for installed commits"
