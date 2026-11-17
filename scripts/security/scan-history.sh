#!/usr/bin/env bash
# Gitleaks with fixed default rules over all history, or over uncommitted edits
# with --staged or --pre-commit. Shared by CI and scan-local.sh. Nothing in the
# repository can hide a finding: its config, .gitleaksignore, inline allows and
# diff attributes are ignored, and merge-only or type-changed content is scanned.
set -euo pipefail
umask 077
usage() { echo "usage: $0 [--staged|--pre-commit] [--report PATH] [REPOSITORY]" >&2; exit 2; }
mode=(--log-opts='--all --full-history --diff-merges=first-parent --diff-filter=d')
report=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --staged|--pre-commit) mode=("$1"); shift ;;
    --report) [ "$#" -ge 2 ] || usage; report=(--report-format json --report-path "$2"); shift 2 ;;
    -*) usage ;;
    *) break ;;
  esac
done
[ "$#" -le 1 ] || usage
repo=$(git -C "${1:-.}" rev-parse --show-toplevel)
git_dir=$(git -C "$repo" rev-parse --absolute-git-dir)
empty_tree=$(git -C "$repo" hash-object -t tree /dev/null)
policy=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-gitleaks.XXXXXX")
trap 'rm -rf "$policy"' EXIT HUP INT TERM
printf '[extend]\nuseDefault = true\n' > "$policy/gitleaks.toml"
: > "$policy/ignore"
printf '* diff=scan\n' > "$policy/attributes"
mkdir "$policy/source"
# Gitleaks always reads <source>/.gitleaksignore, so it scans an empty directory
# with GIT_DIR/GIT_WORK_TREE. Attributes come from an empty tree plus a private
# file that diffs everything as text, so -diff, binary or NUL bytes hide nothing.
cd "$policy/source"
env -u GITLEAKS_CONFIG -u GITLEAKS_CONFIG_TOML -u GIT_CONFIG_PARAMETERS \
  GIT_DIR="$git_dir" GIT_WORK_TREE="$repo" GIT_OPTIONAL_LOCKS=0 GIT_ATTR_SOURCE="$empty_tree" \
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=3 \
  GIT_CONFIG_KEY_0=core.attributesFile GIT_CONFIG_VALUE_0="$policy/attributes" \
  GIT_CONFIG_KEY_1=diff.scan.binary GIT_CONFIG_VALUE_1=false \
  GIT_CONFIG_KEY_2=core.fsmonitor GIT_CONFIG_VALUE_2=false \
  gitleaks git "${mode[@]}" --redact=100 --no-banner --no-color \
    --config "$policy/gitleaks.toml" --gitleaks-ignore-path "$policy/ignore" --ignore-gitleaks-allow \
    ${report[@]+"${report[@]}"} "$policy/source"
