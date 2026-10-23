#!/usr/bin/env bash
# Only disposable CI/VPS jobs opt in; never source this from an interactive profile.
set -euo pipefail
[ "${DOTFILES_DISPOSABLE_CI:-}" = 1 ] || { echo 'Disposable CI opt-in required' >&2; exit 2; }
[ "$#" -gt 0 ] || { echo 'Expected a CI command' >&2; exit 2; }
# Command-scoped config ignores persistent machine routing and clears helpers for
# GitHub. Public fetches need no authentication; any challenge fails closed.
unset GIT_CONFIG_PARAMETERS GIT_CONFIG GIT_ASKPASS SSH_ASKPASS
export GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_COUNT=3
export GIT_CONFIG_KEY_0=credential.https://github.com.helper GIT_CONFIG_VALUE_0=''
export GIT_CONFIG_KEY_1=credential.https://github.com.helper
export GIT_CONFIG_VALUE_1='!f() { printf "quit=true\n"; }; f'
export GIT_CONFIG_KEY_2=credential.https://github.com.username GIT_CONFIG_VALUE_2=anonymous
export GIT_TERMINAL_PROMPT=0
exec "$@"
