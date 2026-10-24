#!/usr/bin/env bash
set -euo pipefail
clean_only=0; allow_help_tags=0; allow_userinfo=0
while :; do
  case "${1:-}" in
    --clean) clean_only=1; shift ;;
    --allow-help-tags) allow_help_tags=1; shift ;;
    --allow-userinfo) allow_userinfo=1; shift ;;
    *) break ;;
  esac
done
[ "$#" -eq 3 ] || { echo "usage: $0 [--clean] [--allow-help-tags] [--allow-userinfo] DIRECTORY ORIGIN FULL_COMMIT" >&2; exit 2; }
dir=$1; origin=$2; sha=$3
fail() { echo "checkout rejected: $dir ($1)" >&2; exit 1; }
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || fail 'expected a full lowercase commit SHA'
[ -d "$dir" ] && [ ! -L "$dir" ] && [ -d "$dir/.git" ] && [ ! -L "$dir/.git" ] || fail 'not a managed repository directory'
# No repository-controlled fsmonitor or hooks may run during these checks.
g() { git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c core.untrackedCache=false -C "$dir" "$@"; }
root=$(g rev-parse --show-toplevel) || fail 'invalid repository'
[ "$(cd "$dir" && pwd -P)" = "$(cd "$root" && pwd -P)" ] || fail 'not the repository root'
actual_origin=$(g remote get-url origin)
# GitHub's optional .git suffix does not change repository identity. All other
# URL components remain strict; userinfo is allowed only for the explicit caller.
printf '%s\0%s' "$actual_origin" "$origin" | python3 -c '
import re,sys
actual,expected=sys.stdin.buffer.read().decode().split("\0")
if any(ord(c)<32 or ord(c)==127 for c in actual+expected): sys.exit(1)
if actual==expected: sys.exit(0)
pattern=r"https://([^/?#]+)/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)"
a,e=re.fullmatch(pattern,actual),re.fullmatch(pattern,expected)
if not a or not e or e[1]!="github.com": sys.exit(1)
host=a[1]
if "@" in host:
 if sys.argv[1]!="1": sys.exit(1)
 host=host.rsplit("@",1)[1]
def repo(value): return value[:-4] if value.endswith(".git") else value
sys.exit(0 if host==e[1] and a[2]==e[2] and repo(a[3])==repo(e[3]) else 1)
' "$allow_userinfo" || fail "origin differs from reviewed origin; expected $origin (optional .git suffix accepted)"
[ "$(g config --get-all remote.origin.url | wc -l | tr -d ' ')" = 1 ] || fail 'multiple origin URLs'
status=$(g status --porcelain=v1 --untracked-files=all --ignored)
if [ "$allow_help_tags" = 1 ]; then
  # Generated Neovim help indexes only. Never exempt tracked changes or code.
  if [ -e "$dir/doc/tags" ] || [ -L "$dir/doc/tags" ]; then
    [ -f "$dir/doc/tags" ] && [ ! -L "$dir/doc/tags" ] && [ ! -L "$dir/doc" ] && [ ! -x "$dir/doc/tags" ] || fail 'unsafe generated help tags'
    status=$(printf '%s\n' "$status" | sed '/^?? doc\/tags$/d; /^!! doc\/tags$/d')
  fi
fi
if [ -n "$status" ]; then
  printf 'Checkout contains local or ignored state; review/back it up without resetting: %s\n' "$dir" >&2
  # Git-quoted relative names only; no file contents or remote URLs are printed.
  printf '%s\n' "$status" | sed -n '1,12p' >&2
  fail 'tracked, untracked, or ignored modifications exist'
fi
if [ "$clean_only" = 0 ]; then
  [ "$(g rev-parse --verify HEAD)" = "$sha" ] || fail 'HEAD differs from reviewed commit'
  [ "$(g cat-file -t "$sha")" = commit ] || fail 'pin is not a commit'
fi
