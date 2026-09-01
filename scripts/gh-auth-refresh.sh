#!/bin/sh
# Refresh the GitHub CLI login from a Git credential store, so `gh` uses the
# same PAT as Git's HTTPS remotes. Run after rotating a PAT or whenever
# `gh auth status` reports an invalid token. Human-run only — agents must not
# invoke this (see docs/github-auth.md, "Agent access boundary").
#
# Usage: gh-auth-refresh.sh [store-file]   (default: personal credentials)
set -eu

STORE="${1:-$HOME/.config/git/personal-credentials}"
[ -r "$STORE" ] || { echo "error: cannot read $STORE" >&2; exit 1; }

token="$(sed -n -E 's#^https://[^:]+:([^@]*)@github\.com/?$#\1#p' "$STORE" | head -1)"
[ -n "$token" ] || { echo "error: no github.com entry found in $STORE" >&2; exit 1; }

printf '%s' "$token" | gh auth login --hostname github.com --with-token
gh auth status
