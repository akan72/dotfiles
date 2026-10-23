#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d /private/tmp/tmux-policy.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
fixture="$tmp/root with spaces"
mkdir -p "$fixture/scripts/security" "$tmp/home/.tmux/plugins/tmux-powerline"
cp "$repo_root/scripts/security/tmux-powerline.sh" "$fixture/scripts/security/"
cat > "$fixture/scripts/security/check-clone.sh" <<'BASH'
#!/usr/bin/env bash
set -eu
[ "$#" = 4 ]
[ "$1" = --allow-userinfo ]
[ "$3" = https://github.com/erikw/tmux-powerline ]
[ "$4" = 6079ace8d534a01d4d964b8b854b223f72edaf4b ]
[ "${CHECK_FAIL:-0}" = 0 ]
BASH
cat > "$tmp/home/.tmux/plugins/tmux-powerline/powerline.sh" <<'BASH'
#!/usr/bin/env bash
printf '%s' "$1" > "$HOME/rendered"
printf 'rendered %s' "$1"
BASH
result="$(HOME="$tmp/home" bash "$fixture/scripts/security/tmux-powerline.sh" left)"
[ "$result" = 'rendered left' ]
[ "$(cat "$tmp/home/rendered")" = left ]
rm "$tmp/home/rendered"
if HOME="$tmp/home" CHECK_FAIL=1 bash "$fixture/scripts/security/tmux-powerline.sh" right > "$tmp/result"; then
  echo 'Expected dirty/unreviewed plugin to be refused' >&2; exit 1
fi
[ "$(cat "$tmp/result")" = 'powerline unverified' ]
[ ! -e "$tmp/home/rendered" ]
if HOME="$tmp/home" bash "$fixture/scripts/security/tmux-powerline.sh" install >/dev/null; then
  echo 'Expected unsupported action refusal' >&2; exit 1
fi
python3 - "$repo_root" <<'PY'
import pathlib,sys
s=(pathlib.Path(sys.argv[1])/'tmux.conf').read_text()
assert '/tpm/tpm' not in s and '@plugin' not in s
assert 'powerline/powerline.sh' not in s
assert s.count('scripts/security/tmux-powerline.sh') == 2
print('Tmux wrapper success/refusal/quoted-path fixtures and no-updater policy passed')
PY
