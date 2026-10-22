#!/usr/bin/env bash
# Fixed default rules; repository config, fingerprints and inline allows cannot hide history.
set -euo pipefail
umask 077
[ "$#" -le 1 ] || { echo "usage: $0 [REPOSITORY]" >&2; exit 2; }
cd -- "${1:-.}"
policy_dir=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-history-policy.XXXXXX")
trap 'rm -rf "$policy_dir"' EXIT HUP INT TERM
printf '[extend]\nuseDefault = true\n' > "$policy_dir/gitleaks.toml"
: > "$policy_dir/ignore"
unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML
gitleaks git --redact=100 --no-banner --no-color \
  --config "$policy_dir/gitleaks.toml" --gitleaks-ignore-path "$policy_dir/ignore" \
  --ignore-gitleaks-allow
