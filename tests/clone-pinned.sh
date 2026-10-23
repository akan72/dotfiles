#!/usr/bin/env bash
set -euo pipefail
repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
export DOTFILES=$repo_root
work=$(mktemp -d "${TMPDIR:-/tmp}/clone-pinned.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
# Extract only the definition; no installer code is executed.
eval "$(sed -n '/^function clone_pinned () {/,/^}/p' "$repo_root/assimilate.sh")"
git() { command git -c core.hooksPath=/dev/null -c core.fsmonitor=false -c commit.gpgsign=false "$@"; }
source_repo=$work/source; remote="$work/remote with spaces.git"; dest=$work/install
git init -q "$source_repo"
git -C "$source_repo" config user.email fixture@example.invalid
git -C "$source_repo" config user.name Fixture
printf 'pinned\n' > "$source_repo/content"
git -C "$source_repo" add content
git -C "$source_repo" commit -qm fixture
sha=$(git -C "$source_repo" rev-parse HEAD)
git init -q --bare "$remote"
git -C "$source_repo" push -q "$remote" HEAD:main
clone_pinned "$remote" "$dest" "$sha"
# The valid repeat must remain offline.
mv "$remote" "$work/offline.git"
clone_pinned "$remote" "$dest" "$sha"
reject() { if clone_pinned "$remote" "$dest" "$sha" >/dev/null 2>&1; then echo 'unsafe checkout accepted' >&2; exit 1; fi; }
printf 'local edit\n' >> "$dest/content"; reject
grep -q 'local edit' "$dest/content"
git -C "$dest" checkout -- content
printf 'staged edit\n' >> "$dest/content"; git -C "$dest" add content; reject
git -C "$dest" reset -q HEAD -- content; git -C "$dest" checkout -- content
printf 'harmless\n' > "$dest/untracked.sh"; reject; test -f "$dest/untracked.sh"; rm "$dest/untracked.sh"
git -C "$dest" remote set-url origin "$work/unexpected.git"; reject
git -C "$dest" remote set-url origin "$remote"
ln -s "$dest" "$work/symlink"
if clone_pinned "$remote" "$work/symlink" "$sha" >/dev/null 2>&1; then exit 1; fi
mkdir "$work/nonrepo"
if clone_pinned "$remote" "$work/nonrepo" "$sha" >/dev/null 2>&1; then exit 1; fi
if clone_pinned "$remote" "$dest" short >/dev/null 2>&1; then exit 1; fi
# A repin with unavailable remote fails without changing existing content.
printf 'next\n' > "$source_repo/content"; git -C "$source_repo" add content; git -C "$source_repo" commit -qm next
next=$(git -C "$source_repo" rev-parse HEAD)
if clone_pinned "$remote" "$dest" "$next" >/dev/null 2>&1; then exit 1; fi
test "$(git -C "$dest" rev-parse HEAD)" = "$sha"
mv "$work/offline.git" "$remote"; git -C "$source_repo" push -q "$remote" HEAD:main
clone_pinned "$remote" "$dest" "$next"
test "$(git -C "$dest" rev-parse HEAD)" = "$next"
mkdir "$dest/doc"
printf 'generated tags\n' > "$dest/doc/tags"
# Ordinary checkouts reject this; Neovim's explicit narrow mode permits it.
if clone_pinned "$remote" "$dest" "$next" >/dev/null 2>&1; then exit 1; fi
clone_pinned "$remote" "$dest" "$next" --allow-help-tags
printf 'untracked Lua\n' > "$dest/doc/evil.lua"
if clone_pinned "$remote" "$dest" "$next" --allow-help-tags >/dev/null 2>&1; then exit 1; fi
rm "$dest/doc/evil.lua"
chmod +x "$dest/doc/tags"
if clone_pinned "$remote" "$dest" "$next" --allow-help-tags >/dev/null 2>&1; then exit 1; fi
# Userinfo is machine-local authentication, never a changed repository identity.
chmod -x "$dest/doc/tags"
rm "$dest/doc/tags"; rmdir "$dest/doc"
check="$repo_root/scripts/security/check-clone.sh"
expected=https://github.com/erikw/tmux-powerline
for url in https://fixture-user@example.invalid/erikw/tmux-powerline https://fixture-user@github.com/wrong/repo https://fixture-user@github.com/erikw/tmux-powerline?query=1 https://fixture-user@github.com:444/erikw/tmux-powerline; do
  git -C "$dest" remote set-url origin "$url"
  if "$check" --allow-userinfo "$dest" "$expected" "$next" >/dev/null 2>&1; then exit 1; fi
done
git -C "$dest" remote set-url origin https://fixture-user@github.com/erikw/tmux-powerline
"$check" --allow-userinfo "$dest" "$expected" "$next"
if "$check" "$dest" "$expected" "$next" >/dev/null 2>&1; then exit 1; fi
# Optional .git is equivalent only for the same canonical GitHub repository.
for actual in https://github.com/erikw/tmux-powerline https://github.com/erikw/tmux-powerline.git; do
  git -C "$dest" remote set-url origin "$actual"
  "$check" "$dest" "$expected" "$next"
  "$check" "$dest" "$expected.git" "$next"
  clone_pinned "$expected" "$dest" "$next" '' --preflight
 done
for actual in https://github.com/erikw/other.git https://github.com/erikw/tmux-powerline.git/ https://github.com:443/erikw/tmux-powerline.git https://example.invalid/erikw/tmux-powerline.git; do
  git -C "$dest" remote set-url origin "$actual"
  if "$check" "$dest" "$expected" "$next" >/dev/null 2>&1; then exit 1; fi
 done
echo 'clone tests passed: offline pin, strict failures, edit preservation, safe repin'

# The same checkout contract must hold for disposable anonymous GitHub routing.
# Run in a subshell so its temporary HOME and local transport never affect callers.
(
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/ci-git-routing.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir "$work/home"
export HOME="$work/home" GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null
unset GIT_CONFIG_COUNT
if "$root/scripts/ci/anonymous-github.sh" true >/dev/null 2>&1; then exit 1; fi
export DOTFILES_DISPOSABLE_CI=1
# shellcheck disable=SC2016 # Assertions intentionally expand in the isolated child.
"$root/scripts/ci/anonymous-github.sh" bash -c '
  test "$(git config --get-urlmatch credential.username https://github.com/folke/lazy.nvim.git)" = anonymous
  test -n "$(git config --get-urlmatch credential.helper https://github.com/folke/lazy.nvim.git)"
  if git config --get-urlmatch credential.username https://example.invalid/repo; then exit 1; fi
  test "$GIT_TERMINAL_PROMPT" = 0
'
test -z "${GIT_CONFIG_COUNT:-}" # wrapper cannot mutate caller environment or persistent config
source_repo="$work/source"
git init -q "$source_repo"
printf 'public fixture\n' > "$source_repo/source.txt"
git -C "$source_repo" add source.txt
git -C "$source_repo" -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit -qm fixture
sha=$(git -C "$source_repo" rev-parse HEAD)
export FIXTURE_REMOTE="$source_repo" FIXTURE_FETCH_MARKER="$work/fetch-called"
cat > "$work/fetch.sh" <<'FIXTURE'
set -euo pipefail
root=$1; dest=$2; sha=$3
export DOTFILES=$root
eval "$(sed -n '/^function clone_pinned () {/,/^}/p' "$root/assimilate.sh")"
git() {
  local args=("$@") i
  for ((i=0;i<${#args[@]};i++)); do
    if [ "${args[$i]}" = fetch ]; then
      # Keep the actual HTTPS origin/preflight checks; transport stays local.
      args[$((i+3))]="$FIXTURE_REMOTE"
      : > "$FIXTURE_FETCH_MARKER"
    fi
  done
  command git "${args[@]}"
}
clone_pinned https://github.com/folke/lazy.nvim.git "$dest" "$sha"
FIXTURE
if bash "$work/fetch.sh" "$root" "$work/refused" "$sha" >"$work/refused.log" 2>&1; then exit 1; fi
test ! -e "$FIXTURE_FETCH_MARKER"
grep -Fq 'Git routing missing' "$work/refused.log"
"$root/scripts/ci/anonymous-github.sh" bash "$work/fetch.sh" "$root" "$work/installed" "$sha"
test -e "$FIXTURE_FETCH_MARKER"
test "$(git -C "$work/installed" rev-parse HEAD)" = "$sha"
rm "$FIXTURE_FETCH_MARKER"
"$root/scripts/ci/anonymous-github.sh" bash "$work/fetch.sh" "$root" "$work/installed" "$sha"
test ! -e "$FIXTURE_FETCH_MARKER"
test ! -e "$HOME/.gitconfig"
printf 'CI anonymous GitHub route: missing route refused, public route selected, local pin fetch/offline repeat passed\n'
)
