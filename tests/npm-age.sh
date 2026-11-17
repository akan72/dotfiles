#!/usr/bin/env bash
set -euo pipefail
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/npm-age.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir "$work/bin"
cat > "$work/bin/npm" <<'STUB'
#!/usr/bin/env bash
set -eu
if [ "$1" = --version ]; then echo "${FIXTURE_NPM_VERSION:-11.19.1}"; exit; fi
if [ "$1 $2" = 'config get' ]; then cat "$FIXTURE_NPM_STATE"; exit; fi
if [ "$1 $2" = 'config set' ]; then
  [ "${FIXTURE_OVERRIDE:-0}" = 1 ] || printf '%s\n' "$4" > "$FIXTURE_NPM_STATE"
  exit
fi
exit 2
STUB
chmod +x "$work/bin/npm"
export PATH="$work/bin:$PATH" FIXTURE_NPM_STATE="$work/value"
for value in null 0 3 7 14; do
  echo "$value" > "$FIXTURE_NPM_STATE"
  bash "$root/scripts/security/npm-age.sh" >/dev/null
  expected=7; [ "$value" != 14 ] || expected=14
  test "$(cat "$FIXTURE_NPM_STATE")" = "$expected"
done
echo nonsense > "$FIXTURE_NPM_STATE"
if bash "$root/scripts/security/npm-age.sh" >/dev/null 2>&1; then exit 1; fi
echo 0 > "$FIXTURE_NPM_STATE"
if FIXTURE_NPM_VERSION=11.18.0 bash "$root/scripts/security/npm-age.sh" >/dev/null 2>&1; then exit 1; fi
if FIXTURE_OVERRIDE=1 bash "$root/scripts/security/npm-age.sh" >/dev/null 2>&1; then exit 1; fi
echo 'npm policy tests passed: null/weak/strict/malformed/unsupported/override'
