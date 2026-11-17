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

# Pinned public fetches ignore this machine's Git config: no credential helper,
# injected config, URL rewrite or prompt can take part. A PATH stub records the
# fetch environment and serves the HTTPS origin from a local fixture.
(
unset -f git
work=$(mktemp -d "${TMPDIR:-/tmp}/clone-anonymous.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
real_git=$(command -v git)
mkdir -p "$work/bin" "$work/home"
"$real_git" init -q "$work/source"
printf 'public fixture\n' > "$work/source/source.txt"
"$real_git" -C "$work/source" add source.txt
"$real_git" -C "$work/source" -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit -qm fixture
sha=$("$real_git" -C "$work/source" rev-parse HEAD)
cat > "$work/bin/git" <<STUB
#!/usr/bin/env bash
if printf '%s\n' "\$@" | grep -qx fetch; then
  printf '%s\n' "global=\${GIT_CONFIG_GLOBAL-unset} nosystem=\${GIT_CONFIG_NOSYSTEM-unset} prompt=\${GIT_TERMINAL_PROMPT-unset} askpass=[\${GIT_ASKPASS-unset}] count=\${GIT_CONFIG_COUNT-unset}" "\$@" > "$work/fetch.log"
  args=(); for a in "\$@"; do if [ "\$a" = origin ]; then a="$work/source"; fi; args+=("\$a"); done
  exec "$real_git" "\${args[@]}"
fi
exec "$real_git" "\$@"
STUB
chmod +x "$work/bin/git"
printf '[credential]\n\thelper = !touch %s/helper-ran\n' "$work" > "$work/home/.gitconfig"
eval "$(sed -n '/^function clone_pinned () {/,/^}/p' "$repo_root/assimilate.sh")"
HOME="$work/home" PATH="$work/bin:$PATH" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0="!touch $work/injected-ran" \
  clone_pinned https://github.com/folke/lazy.nvim.git "$work/installed" "$sha"
test "$("$real_git" -C "$work/installed" rev-parse HEAD)" = "$sha"
grep -Fxq 'global=/dev/null nosystem=1 prompt=0 askpass=[] count=unset' "$work/fetch.log"
grep -Fxq 'credential.helper=' "$work/fetch.log"
test ! -e "$work/helper-ran" && test ! -e "$work/injected-ran"
printf 'Anonymous pinned fetch: machine config, injected config, helpers and prompts excluded\n'
)
