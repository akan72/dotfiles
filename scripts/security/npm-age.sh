#!/usr/bin/env bash
set -euo pipefail
if ! command -v npm >/dev/null 2>&1; then
  echo 'npm age check: npm absent; require this check before any later npm install.' >&2
  exit 0
fi
# Require a known-supported npm baseline for the minimum-release-age policy.
version=$(npm --version)
[[ "$version" =~ ^([0-9]+)\.([0-9]+)\.[0-9]+$ ]] || { echo 'npm version is malformed' >&2; exit 1; }
major=${BASH_REMATCH[1]}; minor=${BASH_REMATCH[2]}
if [ "$major" -lt 11 ] || { [ "$major" -eq 11 ] && [ "$minor" -lt 19 ]; }; then
  echo 'npm >=11.19 is required for this age policy' >&2; exit 1
fi
value=$(npm config get min-release-age)
case "$value" in
  null|undefined|'') value=0 ;;
  *[!0-9]*) echo 'npm minimum release age is malformed; no authentication settings changed' >&2; exit 1 ;;
esac
# Bound before arithmetic to avoid overflow and Bash octal interpretation.
[ "${#value}" -le 5 ] || { echo 'npm minimum release age is out of supported range' >&2; exit 1; }
value=$((10#$value))
if [ "$value" -lt 7 ]; then npm config set min-release-age 7 --location=user; fi
value=$(npm config get min-release-age)
[[ "$value" =~ ^[0-9]{1,5}$ ]] && [ "$((10#$value))" -ge 7 ] || {
  echo 'effective npm release age remains below seven days (check project/environment overrides)' >&2; exit 1;
}
printf 'npm effective minimum release age: %s days\n' "$value"
